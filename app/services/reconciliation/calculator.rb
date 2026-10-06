# frozen_string_literal: true

module Reconciliation
  # Computes the raw "Día de Cuadre" data for one user and period:
  # - Pagos pendientes: active expense recurring templates without a linked
  #   transaction in the period (same semantics as
  #   RecurringTemplate#processed_for_period?, batched into one query).
  # - Saldos por conciliar: app balance vs. the last "real" balance entered
  #   per source, with ok / difference / left_pending / unverified status.
  #
  # Payloads are plain hashes with string amounts/dates, used both for the
  # view and for the persisted ReconciliationState#snapshot.
  class Calculator
    Result = Struct.new(:pending_payments, :balances, :pending_payments_count, :discrepancies_count,
                        :unverified_count, keyword_init: true)

    # Bump whenever the snapshot payload shape changes: persisted states built
    # with an older shape are recalculated transparently on the next visit.
    SNAPSHOT_VERSION = "2"

    # Loans are reconciled through their own payment flow; the cuadre covers
    # money positions: accounts, cash, wallets, standalone debit cards and
    # credit-card debt.
    RECONCILABLE_KINDS = %w[account cash wallet debit_card credit_card].freeze

    class << self
      def call(user:, period: Date.current.strftime("%Y-%m"))
        new(user: user, period: period).call
      end

      # The magnitude the user compares against reality for each kind of
      # source: cash for accounts/wallets, owed amount for credit cards.
      def reconcilable_balance(source)
        source.credit_card? ? source.used_credit : source.balance
      end
    end

    def initialize(user:, period:)
      @user = user
      @period = period
    end

    def call
      pending_payments = build_pending_payments
      balances = build_balances

      Result.new(
        pending_payments: pending_payments,
        balances: balances,
        pending_payments_count: pending_payments.size,
        discrepancies_count: balances.count { |row| row[:status].in?(%w[difference left_pending]) },
        unverified_count: balances.count { |row| row[:status] == "unverified" }
      )
    end

    private

    attr_reader :user, :period

    def month_range
      year, month = period.split("-").map(&:to_i)
      Date.new(year, month, 1).beginning_of_month..Date.new(year, month, 1).end_of_month
    end

    def build_pending_payments
      templates = user.recurring_templates.active.expense.includes(:money_source).ordered
      return [] if templates.empty?

      paid_ids = Transaction.where(user_id: user.id, recurring_template_id: templates, date: month_range)
                            .distinct.pluck(:recurring_template_id)

      templates.reject { |template| paid_ids.include?(template.id) }.map { |template| pending_row(template) }
    end

    def pending_row(template)
      {
        template_id: template.id,
        name: template.description,
        source_label: template.money_source&.name || template.source.to_s.humanize,
        due_date: due_date_for(template)&.iso8601,
        amount: template.amount.to_s,
        debt: template.money_source&.debt_payment_target? || false,
        money_source_id: template.money_source_id
      }
    end

    def due_date_for(template)
      return nil if template.payment_day.nil?

      year, month = period.split("-").map(&:to_i)
      last_day = Date.new(year, month, 1).end_of_month.day
      Date.new(year, month, [ template.payment_day, last_day ].min)
    end

    def build_balances
      snapshots = ReconciliationSnapshot.for_period(user, period).index_by(&:money_source_id)

      reconcilable_sources.filter_map do |source|
        snapshot = snapshots[source.id]
        app_balance = self.class.reconcilable_balance(source)
        balance_row(source, snapshot, app_balance)
      end
    end

    # Debit cards roll their movements into the parent account, so only
    # parentless debit cards get their own row. credit_account is eager loaded
    # because display_name touches it for every credit card.
    def reconcilable_sources
      user.money_sources.active.where(kind: RECONCILABLE_KINDS).includes(:credit_account)
          .reject { |source| source.debit_card? && source.parent_id.present? }
          .sort_by { |source| [ source.kind, source.name.downcase ] }
    end

    def balance_row(source, snapshot, app_balance)
      if snapshot.nil?
        return { source_id: source.id, name: source.display_name, kind: source.kind,
                 app_balance: app_balance.to_s, actual_balance: nil, difference: nil,
                 status: "unverified", checked_at: nil }
      end

      difference = snapshot.actual_balance - app_balance
      status = snapshot.resolution == "left_pending" ? "left_pending" : (difference.zero? ? "ok" : "difference")

      { source_id: source.id, name: source.display_name, kind: source.kind,
        app_balance: app_balance.to_s, actual_balance: snapshot.actual_balance.to_s,
        difference: difference.to_s, status: status, checked_at: snapshot.checked_at&.iso8601 }
    end
  end
end

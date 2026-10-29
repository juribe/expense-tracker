# frozen_string_literal: true

module Reconciliation
  # Computes the raw "Día de Balance" data for one user and period:
  # - Pagos pendientes: active expense recurring templates without a linked
  #   transaction in the period (same semantics as
  #   RecurringTemplate#processed_for_period?, batched into one query).
  # - Saldos por conciliar: current app balance per source plus whether it was
  #   reconciled in the period (ok / difference / left_pending / unverified).
  #
  # Payloads are plain hashes with string amounts/dates, used both for the
  # view and for the persisted ReconciliationState#snapshot.
  class Calculator
    Result = Struct.new(:pending_payments, :balances, :pending_payments_count, :discrepancies_count,
                        :unverified_count, keyword_init: true)

    # Bump whenever the snapshot payload shape changes: persisted states built
    # with an older shape are recalculated transparently on the next visit.
    SNAPSHOT_VERSION = "5"

    # Loans are included through their outstanding balance: the user compares
    # it against the bank figure and can adjust it. Loans without a
    # credit_account have no debt figure to reconcile and are left out.
    RECONCILABLE_KINDS = %w[account cash wallet debit_card credit_card loan].freeze

    class << self
      def call(user:, period: Date.current.strftime("%Y-%m"))
        new(user: user, period: period).call
      end

      # The magnitude the user compares against reality for each kind of
      # source: cash for accounts/wallets, owed amount for credit cards, and
      # the outstanding balance for loans.
      def reconcilable_balance(source)
        return source.outstanding_balance.to_d if source.loan?

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

    # The period key is the calendar month ("YYYY-MM", the historical shape)
    # or the pay cycle start date when the user configured paydays.
    def period_range
      @period_range ||= PayCycle.key_range(user, period)
    end

    def cycle_period?
      !period.match?(/\A\d{4}-\d{2}\z/)
    end

    def build_pending_payments
      templates = user.recurring_templates.active.expense.includes(:money_source, :category).ordered
      return [] if templates.empty?

      range = period_range
      templates.reject do |template|
        transactions = Transaction.where(user_id: user.id, recurring_template_id: template.id, date: range)
        transactions.where(recurring_paid_in_full: true).exists? ||
          transactions.sum { |transaction| transaction.amount.to_d.abs } >= template.amount.to_d
      end.map { |template| pending_row(template) }
    end

    def pending_row(template)
      {
        template_id: template.id,
        name: template.description,
        source_label: template.money_source&.name || template.source.to_s.humanize,
        due_date: due_date_for(template)&.iso8601,
        amount: template.amount.to_s,
        category_name: template.category&.name,
        category_icon: template.category&.icon.presence || "ti-tag",
        debt: template.money_source&.debt_payment_target? || false,
        money_source_id: template.money_source_id
      }
    end

    def due_date_for(template)
      return nil if template.payment_day.nil?

      if cycle_period?
        cycle_due_date(template.payment_day)
      else
        calendar_due_date(template.payment_day)
      end
    end

    # First occurrence of the payment day inside the pay cycle (the day may
    # belong to the next calendar month when the cycle crosses months).
    def cycle_due_date(day)
      range = period_range
      (0..1).each do |months_ahead|
        month = range.begin >> months_ahead
        candidate = clamped_day(month.year, month.month, day)
        return candidate if range.cover?(candidate)
      end
      nil
    end

    def calendar_due_date(day)
      year, month = period.split("-").map(&:to_i)
      last_day = Date.new(year, month, 1).end_of_month.day
      Date.new(year, month, [ day, last_day ].min)
    end

    def clamped_day(year, month, day)
      last_day = Date.new(year, month, 1).end_of_month.day
      Date.new(year, month, [ day, last_day ].min)
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
    # because display_name touches it for every credit card and loans read
    # their debt from it.
    def reconcilable_sources
      user.money_sources.active.where(kind: RECONCILABLE_KINDS).includes(:credit_account)
          .reject { |source| source.debit_card? && source.parent_id.present? }
          .reject { |source| source.loan? && source.credit_account.nil? }
          .sort_by { |source| [ source.kind, source.name.downcase ] }
    end

    # Only the current app balance and whether the source was reconciled in
    # this period are shown. The real balance and its difference are entered
    # inside the Conciliar modal and never persisted.
    def balance_row(source, snapshot, app_balance)
      status = snapshot&.resolution || "unverified"

      { source_id: source.id, name: source.display_name, account_name: source.name,
        institution_name: source.institution_name,
        identifier: source.identifier.presence || source.credit_account&.card_last_four,
        sub_kind: source.sub_kind, kind: source.kind,
        app_balance: app_balance.to_s, status: status,
        checked_at: snapshot&.checked_at&.iso8601 }
    end
  end
end

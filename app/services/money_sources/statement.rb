# frozen_string_literal: true

module MoneySources
  class Statement
    Movement = Struct.new(:date, :created_at, :direction, :amount, :description,
                         :secondary, :category, :movement_type, :related_source,
                         :reference, :record, keyword_init: true)

    Result = Struct.new(:source, :range, :period_label, :opening_balance,
                        :entries_total, :exits_total, :closing_balance,
                        :movements, :total_count, :page, :per_page,
                        keyword_init: true)

    def initialize(user:, source:, period: "current", start_date: nil, end_date: nil,
                   kind: "all", query: nil, page: 1, per_page: 25)
      @user = user
      @source = source
      @period_key = period.to_s.presence || "current"
      @start_date = start_date
      @end_date = end_date
      @kind = kind.to_s.presence || "all"
      @query = query.to_s.strip
      @page = page.to_i.positive? ? page.to_i : 1
      @per_page = per_page.to_i.positive? ? per_page.to_i : 25
    end

    def call
      range = resolve_range
      all_movements = build_movements(range)
      filtered = filter_movements(all_movements)
      paginated = paginate(filtered)

      Result.new(
        source: @source,
        range: range,
        period_label: period_label(range),
        opening_balance: opening_balance(range),
        entries_total: filtered.select { |m| m.direction == "in" }.sum { |m| m.amount.to_d },
        exits_total: filtered.select { |m| m.direction == "out" }.sum { |m| m.amount.to_d },
        closing_balance: nil,
        movements: paginated,
        total_count: filtered.size,
        page: @page,
        per_page: @per_page
      ).tap do |result|
        result.closing_balance = result.opening_balance + result.entries_total - result.exits_total
      end
    end

    private

    attr_reader :user, :source, :period_key, :start_date, :end_date, :kind, :query,
               :page, :per_page

    def resolve_range
      case period_key
      when "previous"
        PayCycle.previous(user).to_range
      when "month"
        Date.current.beginning_of_month..Date.current.end_of_month
      when "lastmonth"
        prev = Date.current.prev_month
        prev.beginning_of_month..prev.end_of_month
      when "7days"
        (Date.current - 6.days)..Date.current
      when "30days"
        (Date.current - 29.days)..Date.current
      when "custom"
        custom_range
      else
        PayCycle.current(user).to_range
      end
    end

    def custom_range
      from = parse_date(start_date)
      to = parse_date(end_date)
      return PayCycle.current(user).to_range if from.nil? || to.nil? || from > to

      from..to
    end

    def parse_date(raw)
      return nil if raw.blank?

      Date.parse(raw)
    rescue Date::Error, ArgumentError
      nil
    end

    def period_label(range)
      "#{I18n.l(range.begin)} – #{I18n.l(range.end)}"
    end

    def build_movements(range)
      movements = []
      movements.concat(transaction_movements(range))
      movements.concat(transfer_movements(range))
      movements.concat(payment_movements(range))
      movements.concat(adjustment_movements(range))
      movements.sort_by { |m| [ m.date, m.created_at || Time.at(0) ] }.reverse
    end

    def transaction_movements(range)
      Transaction.where(user_id: user.id, money_source_id: source.id)
                 .where(date: range)
                 .includes(:category)
                 .map do |transaction|
        Movement.new(
          date: transaction.date,
          created_at: transaction.created_at,
          direction: transaction.kind == "income" ? "in" : "out",
          amount: transaction.amount.to_d.abs,
          description: transaction.description.presence || transaction.kind.humanize,
          secondary: nil,
          category: transaction.category,
          movement_type: transaction_movement_type(transaction),
          related_source: nil,
          reference: transaction.id,
          record: transaction
        )
      end
    end

    def transaction_movement_type(transaction)
      return transaction.kind == "income" ? "Ingreso" : "Gasto" unless source.debt?

      if source.credit_card?
        transaction.kind == "income" ? "Pago" : "Compra"
      elsif source.revolving?
        transaction.kind == "income" ? "Pago" : "Uso"
      else
        transaction.kind == "income" ? "Pago" : "Cargo"
      end
    end

    def transfer_movements(range)
      movements = []
      Transfer.where(user_id: user.id, from_source_id: source.id)
              .where(date: range)
              .includes(:to_source)
              .each do |transfer|
        movements << Movement.new(
          date: transfer.date,
          created_at: transfer.created_at,
          direction: "out",
          amount: transfer.amount.to_d,
          description: transfer.note.presence || "Transferencia",
          secondary: transfer.to_source&.name,
          category: nil,
          movement_type: transfer_movement_type(transfer, incoming: false),
          related_source: transfer.to_source,
          reference: transfer.id,
          record: transfer
        )
      end
      Transfer.where(user_id: user.id, to_source_id: source.id)
              .where(date: range)
              .includes(:from_source)
              .each do |transfer|
        movements << Movement.new(
          date: transfer.date,
          created_at: transfer.created_at,
          direction: "in",
          amount: transfer.amount.to_d,
          description: transfer.note.presence || "Transferencia",
          secondary: transfer.from_source&.name,
          category: nil,
          movement_type: transfer_movement_type(transfer, incoming: true),
          related_source: transfer.from_source,
          reference: transfer.id,
          record: transfer
        )
      end
      movements
    end

    def transfer_movement_type(transfer, incoming:)
      return incoming ? "Transferencia recibida" : "Transferencia enviada" unless source.debt?

      if incoming
        extra_transfer_ids.include?(transfer.id) ? "Abono" : "Pago"
      elsif source.credit_card?
        "Avance"
      elsif source.revolving?
        "Transferencia"
      else
        "Desembolso"
      end
    end

    def payment_movements(range)
      return [] unless source.debt?

      source.payments.where(date: range).includes(:expense).filter_map do |payment|
        principal = effective_principal(payment)
        # A payment that never moved the debt (same-card payment or
        # interest-only) is still in the Payments tab and in the funding
        # source statement, but it is not a movement of this debt.
        next if principal.zero?

        Movement.new(
          date: payment.date,
          created_at: payment.created_at,
          direction: "in",
          amount: principal,
          description: payment.expense.description.presence || "Pago de deuda",
          secondary: payment_secondary(payment),
          category: payment.expense.category,
          movement_type: extra_payment_ids.include?(payment.id) ? "Abono" : "Pago",
          related_source: payment.expense.money_source,
          reference: payment.id,
          record: payment
        )
      end
    end

    def effective_principal(payment)
      return 0.to_d if source.credit_card? && payment.expense_money_source_id == source.id

      payment.principal_amount.to_d
    end

    def payment_secondary(payment)
      components = [
        [ "Capital", payment.principal_amount ],
        [ "Intereses", payment.interest_amount ],
        [ "Seguros", payment.insurance_amount ],
        [ "Otros", payment.other_amount ]
      ].filter_map do |label, value|
        next if value.to_d.zero?

        "#{label}: #{MoneyFormat.currency(value)}"
      end

      [ payment.expense.money_source&.name, *components ].compact.join(" · ")
    end

    # Extra payments are not separate ledger rows: an amortizing abono is a
    # Payment and a revolving abono is a Transfer. The link only relabels the
    # derived movement so the extracto distinguishes it without duplicating it.
    def extra_payment_ids
      @extra_payment_ids ||= CreditExtraPayment.where(money_source_id: source.id)
                                                .where.not(payment_id: nil)
                                                .pluck(:payment_id)
                                                .to_set
    end

    def extra_transfer_ids
      @extra_transfer_ids ||= CreditExtraPayment.where(money_source_id: source.id)
                                                 .where.not(transfer_id: nil)
                                                 .pluck(:transfer_id)
                                                 .to_set
    end

    def adjustment_movements(range)
      records = adjustment_records
      return [] if records.empty?

      records.where(effective_date: range).map do |adjustment|
        Movement.new(
          date: adjustment.effective_date,
          created_at: adjustment.created_at,
          direction: adjustment_direction(adjustment),
          amount: adjustment.delta.to_d.abs,
          description: adjustment.note.presence || "Ajuste de saldo",
          secondary: nil,
          category: nil,
          movement_type: "Ajuste de saldo",
          related_source: nil,
          reference: adjustment.id,
          record: adjustment
        )
      end
    end

    # Debt adjustments are stored with different signs per product:
    # cards keep the correction in the negative cash balance, while loans keep
    # it in the positive outstanding balance. Normalize both to the statement's
    # direction (in = debt reduction, out = debt increase).
    def adjustment_direction(adjustment)
      delta = adjustment.delta.to_d
      return delta.positive? ? "in" : "out" unless source.debt?

      debt_change = source.credit_card? ? -delta : delta
      debt_change.positive? ? "out" : "in"
    end

    def adjustment_records
      BalanceAdjustment.where(user_id: user.id, money_source_id: source.id)
    end

    def has_adjustment_records?
      adjustment_records.exists?
    end

    def filter_movements(movements)
      filtered = movements
      filtered = filtered.select { |m| m.direction == kind } if kind.in?(%w[in out])
      if query.present?
        q = query.downcase
        filtered = filtered.select do |m|
          [ m.description, m.secondary, m.movement_type, m.category&.name,
            m.related_source&.name ].compact.join(" ").downcase.include?(q)
        end
      end
      filtered
    end

    def paginate(movements)
      offset = (page - 1) * per_page
      movements[offset, per_page] || []
    end

    def opening_balance(range)
      return opening_balance_for_loan(range) if source.loan?

      total = source.starting_balance.to_d

      total += Transaction.where(user_id: user.id, money_source_id: source.id)
                          .where("date < ?", range.begin)
                          .sum(:amount).to_d

      outgoing = Transfer.where(user_id: user.id, from_source_id: source.id)
                         .where("date < ?", range.begin)
                         .sum(:amount).to_d
      incoming = Transfer.where(user_id: user.id, to_source_id: source.id)
                         .where("date < ?", range.begin)
                         .sum(:amount).to_d
      total += -outgoing + incoming

      if has_adjustment_records?
        total += adjustment_records.where("effective_date < ?", range.begin).sum(:delta).to_d
      elsif source.balance_offset.present? &&
            (source.balance_offset_at.nil? || source.balance_offset_at.to_date < range.begin)
        total += source.balance_offset.to_d
      end

      # Card payments move the cached balance through Payments::BalanceEffect
      # without creating a transaction on the card, so the statement's opening
      # balance must add their principal to stay aligned with the real debt.
      total += card_payment_principal_before(range) if source.credit_card?

      total
    end

    # Loans keep their debt on credit_account.outstanding_balance (positive),
    # so the statement uses the equivalent signed balance (negative). The
    # current outstanding is the anchor: reversing every operation from the
    # period start onwards yields the opening debt, including any initial
    # outstanding entered on the loan form and historical adjustments.
    def opening_balance_for_loan(range)
      -(source.outstanding_balance.to_d - loan_debt_change_since(range.begin))
    end

    def loan_debt_change_since(date)
      change = -Transaction.where(user_id: user.id, money_source_id: source.id)
                           .where("date >= ?", date)
                           .sum(:amount).to_d
      change += Transfer.where(user_id: user.id, from_source_id: source.id)
                        .where("date >= ?", date)
                        .sum(:amount).to_d
      change -= Transfer.where(user_id: user.id, to_source_id: source.id)
                        .where("date >= ?", date)
                        .sum(:amount).to_d
      change -= Payment.where(user_id: user.id, money_source_id: source.id)
                       .where("date >= ?", date)
                       .sum(:principal_amount).to_d
      change += adjustment_records.where("effective_date >= ?", date).sum(:delta).to_d
      change
    end

    def card_payment_principal_before(range)
      source.payments.includes(:expense).where("date < ?", range.begin).sum do |payment|
        effective_principal(payment)
      end.to_d
    end
  end
end

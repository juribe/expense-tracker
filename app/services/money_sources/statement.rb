# frozen_string_literal: true

module MoneySources
  class Statement
    Movement = Struct.new(:date, :created_at, :direction, :amount, :description,
                         :secondary, :category, :movement_type, :related_source,
                         :reference, keyword_init: true)

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
          movement_type: transaction.kind == "income" ? "Ingreso" : "Gasto",
          related_source: nil,
          reference: transaction.id
        )
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
          movement_type: "Transferencia enviada",
          related_source: transfer.to_source,
          reference: transfer.id
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
          movement_type: "Transferencia recibida",
          related_source: transfer.from_source,
          reference: transfer.id
        )
      end
      movements
    end

    def adjustment_movements(range)
      records = adjustment_records
      return [] if records.empty?

      records.where(effective_date: range).map do |adjustment|
        Movement.new(
          date: adjustment.effective_date,
          created_at: adjustment.created_at,
          direction: adjustment.delta.to_d.positive? ? "in" : "out",
          amount: adjustment.delta.to_d.abs,
          description: adjustment.note.presence || "Ajuste de saldo",
          secondary: nil,
          category: nil,
          movement_type: "Ajuste de saldo",
          related_source: nil,
          reference: adjustment.id
        )
      end
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

      total
    end
  end
end
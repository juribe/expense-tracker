# frozen_string_literal: true

module Mcp
  # ToolArguments
  # Argument parsing and ownership checks shared by MCP tools. Every lookup
  # starts from the authenticated user, so a foreign id is never found.
  module ToolArguments
    private

    def parse_date(value, field:)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error, ArgumentError
      raise Mcp::Error.new("INVALID_DATE_RANGE", "#{field} must be an ISO 8601 date (YYYY-MM-DD).")
    end

    def parse_month(value)
      Date.iso8601("#{value}-01")
    rescue Date::Error, ArgumentError
      raise Mcp::Error.new("INVALID_DATE_RANGE", "month must use the YYYY-MM format.")
    end

    # Explicit bounds win; otherwise the user's current financial cycle or
    # calendar month, matching the dashboard and the reports.
    def date_range(start_date: nil, end_date: nil, month: nil)
      if start_date.present? || end_date.present?
        from = parse_date(start_date, field: "start_date") || Date.current.beginning_of_month
        to = parse_date(end_date, field: "end_date") || Date.current
        raise Mcp::Error.new("INVALID_DATE_RANGE", "start_date must be on or before end_date.") if to < from

        from..to
      else
        anchor = month.present? ? parse_month(month) : Date.current
        Reports::Period.new(preset: "this_month", date: anchor, user: user).range
      end
    end

    def find_category!(id, type: nil)
      category_id = UuidParams.normalize(id)
      category = category_id && Category.for_user(user).find_by(id: category_id)
      return category if category && (type.nil? || category.category_type == type)

      raise Mcp::Error.new("INVALID_CATEGORY", "The selected category is not available.")
    end

    def find_money_source!(id, error_code: "INVALID_MONEY_SOURCE")
      source_id = UuidParams.normalize(id)
      source = source_id && user.money_sources.find_by(id: source_id)
      return source if source

      raise Mcp::Error.new(error_code, "The selected money source is not available.")
    end

    def paginated(scope, limit:, offset:)
      total = scope.count
      records = scope.limit(limit).offset(offset)
      has_more = offset + limit < total

      [ records, { limit: limit, offset: offset, total: total, has_more: has_more,
                   next_offset: has_more ? offset + limit : nil } ]
    end

    def required_date!(value, field: "date")
      parse_date(value, field: field) ||
        raise(Mcp::Error.new("INVALID_DATE_RANGE", "#{field} is required."))
    end

    def positive_amount!(value)
      amount = BigDecimal(MoneyFormat.normalize(value).to_s)
      raise Mcp::Error.new("INVALID_ARGUMENT", "amount must be greater than zero.") unless amount.positive?

      amount
    rescue ArgumentError, TypeError
      raise Mcp::Error.new("INVALID_ARGUMENT", "amount must be a valid positive number.")
    end

    def idempotency_key!(value)
      return nil if value.blank?

      UuidParams.normalize(value) ||
        raise(Mcp::Error.new("INVALID_ARGUMENT", "idempotency_key must be a UUID."))
    end

    def ensure_payment_source!(source)
      return source if source.payment_source?

      raise Mcp::Error.new("INVALID_MONEY_SOURCE", "The selected money source cannot move money for expenses.")
    end

    def find_pocket!(id)
      source = user.money_sources.find(UuidParams.normalize(id))
      return source if source.pocket?

      raise Mcp::Error.new("INVALID_POCKET", "The selected money source is not a pocket.")
    end

    def movement_error_code(record, field: :amount)
      record.errors.of_kind?(field, :insufficient_balance) ? "INSUFFICIENT_FUNDS" : "INVALID_ARGUMENT"
    end

    def record_error_code(record)
      record.errors.of_kind?(:money_source, :insufficient_balance) ? "INSUFFICIENT_FUNDS" : "INVALID_ARGUMENT"
    end
  end
end

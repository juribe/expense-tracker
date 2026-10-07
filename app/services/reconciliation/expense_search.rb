# frozen_string_literal: true

module Reconciliation
  # Finds candidate expenses for the "Asignar pago" modal: newest first,
  # matching the search text and/or the expected amount, dated inside the
  # cuadre period month (only an in-period expense can clear the pending
  # row), and skipping any expense already linked to a recurring template.
  # Includes this month's candidates so Gmail-created expenses show up as
  # selectable results.
  class ExpenseSearch
    LIMIT = 8

    def self.call(user:, query: nil, amount: nil, template_id: nil, period: nil)
      scope = user.expenses.where(recurring_template_id: nil).order(date: :desc, created_at: :desc)

      if period.present?
        scope = scope.where(date: PayCycle.key_range(user, period))
      end

      query = query.to_s.strip
      if query.present?
        like = "%#{Transaction.sanitize_sql_like(query)}%"
        scope = scope.where("description ILIKE :like OR source ILIKE :like", like: like)
      end

      if amount.present?
        target = amount.to_s.to_d
        if target.positive?
          tolerance = [ target * 0.05, 1000 ].max
          scope = scope.where(amount: (-(target + tolerance))..(-(target - tolerance)))
        end
      end

      scope.limit(LIMIT)
    end
  end
end

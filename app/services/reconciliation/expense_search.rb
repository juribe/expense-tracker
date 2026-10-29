# frozen_string_literal: true

module Reconciliation
  # Finds candidate expenses for the "Asignar pago" modal: newest first,
  # matching the search text and/or the expected amount, dated inside the
  # reconciliation period, filtered to the recurring template's category, and
  # skipping any expense already linked to a recurring template. Includes
  # this period's candidates so Gmail-created expenses show up as selectable
  # results.
  class ExpenseSearch
    LIMIT = 8

    def self.call(user:, query: nil, amount: nil, template_id: nil, period: nil)
      scope = user.expenses.where(recurring_template_id: nil).order(date: :desc, created_at: :desc)

      if template_id.present?
        template = user.recurring_templates.find_by(id: template_id)
        return scope.none if template.nil?

        scope = scope.where(category_id: template.category_id)
      end

      if period.present?
        scope = scope.where(date: PayCycle.key_range(user, period))
      end

      query = query.to_s.strip
      if query.present?
        like = "%#{Transaction.sanitize_sql_like(query)}%"
        numeric = numeric_query(query)
        if numeric
          tolerance = [ numeric * 0.05, 1000 ].max
          scope = scope.where(
            "description ILIKE :like OR source ILIKE :like OR amount BETWEEN :min AND :max",
            like: like, min: -(numeric + tolerance), max: -(numeric - tolerance)
          )
        else
          scope = scope.where("description ILIKE :like OR source ILIKE :like", like: like)
        end
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

    def self.numeric_query(query)
      cleaned = query.delete("^0-9.,")
      return nil if cleaned.blank?
      return nil unless query.match?(/\A[\s$]*[\d.,]+\z/)

      value = MoneyFormat.normalize(cleaned).to_d
      value.positive? ? value : nil
    end

    private_class_method :numeric_query
  end
end

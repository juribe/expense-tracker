# frozen_string_literal: true

module Reconciliation
  # Finds existing movements (expenses and incomes) that could explain a
  # balance difference, for the "Buscar movimiento" action in the Conciliar
  # modal. Newest first; matches description text and/or amount.
  class MovementSearch
    LIMIT = 8

    def self.call(user:, query: nil, amount: nil)
      scope = user.transactions.order(date: :desc, created_at: :desc)

      query = query.to_s.strip
      if query.present?
        like = "%#{Transaction.sanitize_sql_like(query)}%"
        scope = scope.where("description ILIKE :like OR source ILIKE :like", like: like)
      end

      if amount.present?
        target = amount.to_s.to_d
        if target.positive?
          tolerance = [ target * 0.05, 1000 ].max
          scope = scope.where(amount: (-(target + tolerance))..(target + tolerance))
        end
      end

      scope.limit(LIMIT)
    end
  end
end

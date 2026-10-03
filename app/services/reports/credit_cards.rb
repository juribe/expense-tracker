# frozen_string_literal: true

# Reports::CreditCards
# Per credit card: limit, usage, utilization and the period's activity —
# purchases (card expenses without a Payment), payments (Payment records and
# transfers into the card) and the interest/fees components of those payments.
#
# Methods: call
#
# Example: Reports::CreditCards.new(user: user, filter: filter).call[:cards]
class Reports::CreditCards < Reports::Base
  def call
    cards = card_sources
    purchases = grouped_purchases(period.range)
    payments = grouped_payments(period.range)
    transfers = grouped_transfers(period.range)

    rows = cards.map { |card| card_row(card, purchases, payments, transfers) }

    {
      period: period,
      cards: rows,
      totals: totals(rows)
    }
  end

  private

  def card_sources
    scope = user.money_sources.active.where(kind: "credit_card").includes(:credit_account)
    scope = scope.where(id: filter.active_source_id) if filter.active_source_id
    scope
  end

  def card_row(card, purchases, payments, transfers)
    limit = card.credit_limit.to_d
    used = card.used_credit.to_d
    bought = purchases.fetch(card.id, { total: 0.to_d, count: 0 })
    paid = payments.fetch(card.id, { amount: 0.to_d, interest: 0.to_d, insurance: 0.to_d, other: 0.to_d })
    {
      id: card.id, name: card.name, display_name: card.display_name,
      limit: limit.positive? ? limit : nil,
      used: used,
      available: card.available_credit&.to_d,
      utilization_pct: limit.positive? ? (used / limit * 100).round(1) : nil,
      purchases: bought[:total],
      purchases_count: bought[:count],
      payments: paid[:amount] + transfers.fetch(card.id, 0.to_d),
      interest: paid[:interest],
      fees: paid[:insurance] + paid[:other],
      opening: nil,
      closing: used
    }
  end

  def grouped_purchases(range)
    filter.expense_scope(range).where(money_source_id: card_ids).where.missing(:payments)
          .group(:money_source_id)
          .pluck(Arel.sql("transactions.money_source_id"),
                 Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
          .to_h { |source_id, total, count| [ source_id, { total: total.to_d, count: count.to_i } ] }
  end

  def grouped_payments(range)
    Payment.for_user(user)
           .where(money_source_id: card_ids, date: range)
           .group(:money_source_id)
           .pluck(Arel.sql("payments.money_source_id"),
                  Arel.sql("SUM(payments.amount)"),
                  Arel.sql("SUM(payments.interest_amount)"),
                  Arel.sql("SUM(payments.insurance_amount)"),
                  Arel.sql("SUM(payments.other_amount)"))
           .to_h do |source_id, amount, interest, insurance, other|
      [ source_id, { amount: amount.to_d, interest: interest.to_d,
                     insurance: insurance.to_d, other: other.to_d } ]
    end
  end

  def grouped_transfers(range)
    Transfer.for_user(user)
            .where(date: range)
            .where("from_source_id NOT IN (?)", MoneySource.debt_payment_targets.select(:id))
            .group(:to_source_id)
            .sum(:amount)
            .transform_values(&:to_d)
  end

  def card_ids
    card_sources.map(&:id)
  end

  def totals(rows)
    limits = rows.filter_map { |row| row[:limit] }
    used = rows.sum { |row| row[:used] }
    {
      limit: limits.sum, used: used,
      available: limits.sum.positive? ? limits.sum - used : nil,
      utilization_pct: limits.sum.positive? ? (used / limits.sum * 100).round(1) : nil,
      purchases: rows.sum { |row| row[:purchases] },
      payments: rows.sum { |row| row[:payments] },
      interest: rows.sum { |row| row[:interest] },
      fees: rows.sum { |row| row[:fees] }
    }
  end
end

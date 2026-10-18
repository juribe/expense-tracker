# frozen_string_literal: true

# CategoryInsight
# Deterministic savings-opportunity estimate for a subcategory, built from the
# user's actual historical spending over completed financial cycles plus a
# configured suggested savings rate. Advice comes from SubcategorySavingTip.
#
# Methods: call, average_spending, estimated_savings, completed_cycles
#
# Example: CategoryInsight.new(user: user, category: category).call
class CategoryInsight
  COMPLETED_CYCLES = 3

  attr_reader :user, :category, :date

  def initialize(user:, category: nil, subcategory: nil, date: Date.current)
    @user = user
    @category = category || subcategory
    @date = date.to_date
  end

  def self.call(user:, category: nil, subcategory: nil, date: Date.current)
    new(user: user, category: category, subcategory: subcategory, date: date).call
  end

  def call
    totals = completed_cycle_totals
    spending_cycles = totals.select(&:positive?)
    avg = spending_cycles.empty? ? nil : (spending_cycles.sum / spending_cycles.size)
    rate = category&.suggested_savings_percentage
    eligible = rate.present? && rate.to_d.positive? && eligible_category?
    estimate = (avg.present? && eligible) ? (avg * rate.to_d / 100) : nil

    {
      category: category,
      saving_potential: category&.savings_potential,
      suggested_rate: rate,
      suggested_saving_rate: rate,
      suggested_savings_rate: rate,
      suggested_savings_percentage: rate,
      average_spending: avg,
      average_spending_amount: avg,
      estimated_savings: estimate,
      estimated_savings_amount: estimate,
      completed_cycles: COMPLETED_CYCLES,
      cycles_with_spending: spending_cycles.size,
      cycle_totals: totals,
      eligible: eligible,
      tips: (category&.saving_tips&.active&.ordered || []),
      advice: (category&.saving_tips&.active&.ordered || [])
    }
  end

  def average_spending
    call[:average_spending]
  end

  def estimated_savings
    call[:estimated_savings]
  end

  def completed_cycles
    PayCycle.back(user, COMPLETED_CYCLES + 1, anchor: date).first(COMPLETED_CYCLES)
  end

  private

  def completed_cycle_totals
    completed_cycles.map { |cycle| spending_for(cycle.to_range) }
  end

  def spending_for(range)
    Expense.for_user(user)
           .where(category_id: category.id)
           .where(date: range)
           .where.missing(:payments)
           .sum(Arel.sql("ABS(transactions.amount)"))
           .to_d
  end

  def eligible_category?
    return true if category&.suggested_savings_percentage.to_d.positive?

    false
  end
end

CategoryInsights = CategoryInsight unless defined?(CategoryInsights)
CategoryInsightCalculator = CategoryInsight unless defined?(CategoryInsightCalculator)
CategoryInsightService = CategoryInsight unless defined?(CategoryInsightService)

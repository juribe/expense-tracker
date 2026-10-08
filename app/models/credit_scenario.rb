# frozen_string_literal: true

# CreditScenario
# A saved "what-if" simulation against a loan's credit projection (extra
# principal payment, recurring extra, periodic extra or target payoff).
# Max 3 per money source; results are computed by the Credits::Simulator
# engine and stored as a snapshot so the comparison view never recalculates.
#
# Associations: belongs_to :money_source
# Methods: KINDS, limit validation
#
# Example: Credits::Scenarios::Create.call(money_source:, kind:, name:, params:)
class CreditScenario < ApplicationRecord
  KINDS = %w[one_time_extra recurring_extra target_payoff].freeze

  MAX_PER_CREDIT = 3

  belongs_to :money_source

  validates :name, :kind, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :params, :results, presence: true
  validate :scenarios_limit, on: :create

  private

  def scenarios_limit
    return if money_source.nil?

    errors.add(:base, :scenario_limit) if money_source.credit_scenarios.count >= MAX_PER_CREDIT
  end
end

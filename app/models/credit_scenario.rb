# frozen_string_literal: true

# CreditScenario
# A saved "what-if" simulation of an extraordinary payment on a loan.
# The kind IS the application type (reduce_term, reduce_installment,
# prepay_installments, target_payoff); results are computed by
# Credits::Simulator and stored as a snapshot. Max 3 per money source.
#
# Associations: belongs_to :money_source
# Methods: KINDS, MAX_PER_CREDIT
class CreditScenario < ApplicationRecord
  KINDS = Credits::Simulator::STRATEGIES.freeze

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

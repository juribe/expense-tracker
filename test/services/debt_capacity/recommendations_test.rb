# frozen_string_literal: true

require "test_helper"

class DebtCapacityRecommendationsTest < ActiveSupport::TestCase
  test "prioritizes the debt with the highest financial cost after urgent obligations" do
    recommendations = DebtCapacity::Recommendations.new(debts: [
      debt(name: "Hipotecario", balance: 80_000_000, installment: 1_500_000, annual_rate: 10.0,
           monthly_interest: 640_000, status: :current),
      debt(name: "Tarjeta", balance: 3_000_000, installment: 250_000, annual_rate: 28.0,
           monthly_interest: 62_000, status: :current)
    ]).call

    assert_equal "Tarjeta", recommendations[:prioritize].first[:name]
    assert_match(/tasa|interés/i, recommendations[:prioritize].first[:reason])
    assert_equal [ "Hipotecario" ], recommendations[:keep_current].map { |item| item[:name] }
  end

  test "keeps an ordinary current debt out of the priority group" do
    recommendations = DebtCapacity::Recommendations.new(debts: [
      debt(name: "Crédito vigente", balance: 8_000_000, installment: 400_000, annual_rate: 18.0,
           monthly_interest: 110_000, status: :current)
    ]).call

    assert_empty recommendations[:prioritize]
    assert_equal [ "Crédito vigente" ], recommendations[:keep_current].map { |item| item[:name] }
  end

  test "places overdue or at-risk obligations in the keep-current group" do
    recommendations = DebtCapacity::Recommendations.new(debts: [
      debt(name: "Crédito atrasado", balance: 4_000_000, installment: 300_000, annual_rate: 20.0,
           monthly_interest: 60_000, status: :overdue)
    ]).call

    assert_equal [ "Crédito atrasado" ], recommendations[:keep_current].map { |item| item[:name] }
    assert_empty recommendations[:prioritize]
  end

  test "suggests negotiation when the installment is materially high relative to income" do
    recommendations = DebtCapacity::Recommendations.new(
      debts: [ debt(name: "Crédito personal", balance: 20_000_000, installment: 4_500_000,
                    annual_rate: 22.0, monthly_interest: 330_000, status: :current) ],
      monthly_income: 10_000_000
    ).call

    assert_equal [ "Crédito personal" ], recommendations[:negotiate].map { |item| item[:name] }
    assert_match(/plazo|costo|cuota/i, recommendations[:negotiate].first[:reason])
  end

  test "does not recommend a debt with missing financial data as the best payment target" do
    recommendations = DebtCapacity::Recommendations.new(debts: [
      debt(name: "Crédito incompleto", balance: nil, installment: nil, annual_rate: nil,
           monthly_interest: nil, status: :current)
    ]).call

    assert_empty recommendations[:prioritize]
    assert recommendations[:data_gaps].any? { |gap| gap[:name] == "Crédito incompleto" }
  end

  private

  def debt(name:, balance:, installment:, annual_rate:, monthly_interest:, status:)
    {
      name: name,
      balance: balance&.to_d,
      monthly_installment: installment&.to_d,
      annual_rate: annual_rate&.to_d,
      monthly_interest: monthly_interest&.to_d,
      status: status
    }
  end
end

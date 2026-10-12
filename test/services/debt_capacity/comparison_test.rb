# frozen_string_literal: true

require "test_helper"

class DebtCapacityComparisonTest < ActiveSupport::TestCase
  test "simulates a payment against the selected debt while keeping the installment for a shorter term" do
    comparison = DebtCapacity::Comparison.new(debts: debts, debt_id: 1, amount: 1_000_000, mode: "reduce_term").call

    assert comparison[:available]
    assert_equal "Visa", comparison[:selected_debt][:name]
    assert_equal 1_000_000.to_d, comparison[:amount]
    assert_equal 3_000_000.to_d, comparison[:current][:balance]
    assert_equal 2_000_000.to_d, comparison[:after][:balance]
    assert_equal comparison[:current][:installment], comparison[:after][:installment]
    assert_operator comparison[:after][:remaining_installments], :<, comparison[:current][:remaining_installments]
    assert_operator comparison[:interest_saving], :>, 0
  end

  test "recalculates the installment when the user chooses a lower payment" do
    comparison = DebtCapacity::Comparison.new(debts: debts, debt_id: 2, amount: 1_000_000,
                                               mode: "reduce_installment").call

    assert comparison[:available]
    assert_operator comparison[:after][:installment], :<, comparison[:current][:installment]
    assert_equal 1_000_000.to_d, comparison[:after][:balance]
  end

  test "uses the requested installment count for a revolving credit and only reduces the installment" do
    comparison = DebtCapacity::Comparison.new(
      debts: debts, debt_id: 2, amount: 1_000_000, mode: "reduce_term", installment_count: 12
    ).call

    assert comparison[:available]
    assert_equal "reduce_installment", comparison[:mode]
    assert_equal 12, comparison[:after][:remaining_installments]
    assert_operator comparison[:after][:installment], :<, comparison[:current][:installment]
  end

  test "defaults revolving simulations to 48 installments" do
    comparison = DebtCapacity::Comparison.new(
      debts: debts, debt_id: 2, amount: 1_000_000, mode: "reduce_installment"
    ).call

    assert_equal 48, comparison[:after][:remaining_installments]
  end

  test "selects the highest-rate debt when no debt is selected" do
    comparison = DebtCapacity::Comparison.new(debts: debts, amount: 500_000).call

    assert_equal "Visa", comparison[:selected_debt][:name]
  end

  test "returns an unavailable result when debt data cannot be simulated" do
    comparison = DebtCapacity::Comparison.new(debts: [ { name: "Sin datos" } ]).call

    assert_not comparison[:available]
  end

  private

  def debts
    [
      { id: 1, name: "Visa", balance: 3_000_000.to_d, monthly_installment: 250_000.to_d,
        monthly_interest: 62_000.to_d, annual_rate: 28.to_d, interest_rate_type: "effective_annual",
        payment_frequency: "monthly" },
      { id: 2, name: "Rotativo", balance: 2_000_000.to_d, monthly_installment: 400_000.to_d,
        monthly_interest: 40_000.to_d, annual_rate: 24.to_d, interest_rate_type: "effective_annual",
        payment_frequency: "monthly", sub_kind: "revolving" }
    ]
  end
end

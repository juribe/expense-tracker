# frozen_string_literal: true

require "test_helper"

class GmfCalculatorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Calc User", email: "calc@example.com", password: "password123")
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100_000_000, gmf_exempt: true)
    GmfUvtYear.find_or_create_by!(year: 2026) { |r| r.value = 52374.00 }
  end

  test "exempt account below limit generates no gmf" do
    result = Gmf::Calculator.call(user: @user, origin_money_source: @account,
                                  operation_type: :expense_payment, date: Date.new(2026, 11, 10),
                                  amount: 10_000_000)
    assert result.taxed?
    assert_equal 0.to_d, result.gmf_amount
    assert_equal 10_000_000.to_d, result.covered_by_exemption
  end

  test "exempt account exceeding limit generates gmf on excess" do
    limit = Gmf::Uvt.exemption_limit(2026)
    acc = GmfMonthlyAccumulator.for(user: @user, money_source: @account, date: Date.new(2026, 11, 1))
    Gmf::MonthlyAccumulator.add!(acc, amount: limit - 1000, covered: limit - 1000, taxable: 0, gmf: 0)
    result = Gmf::Calculator.call(user: @user, origin_money_source: @account,
                                  operation_type: :expense_payment, date: Date.new(2026, 11, 2),
                                  amount: 5000)
    assert result.gmf_amount > 0
    assert_equal 1000.to_d, result.covered_by_exemption
    assert_equal 4000.to_d, result.taxable_excess
  end

  test "non-exempt account generates gmf from first peso" do
    other = @user.money_sources.create!(name: "Otra", kind: "account", starting_balance: 10_000_000)
    result = Gmf::Calculator.call(user: @user, origin_money_source: other,
                                  operation_type: :expense_payment, date: Date.new(2026, 11, 10),
                                  amount: 100_000)
    assert_equal (100_000 * 0.004).to_d, result.gmf_amount
  end

  test "credit card purchase is not taxable" do
    card = @user.money_sources.create!(name: "Card", kind: "credit_card", starting_balance: 0)
    result = Gmf::Calculator.call(user: @user, origin_money_source: card,
                                  operation_type: :credit_card_purchase, date: Date.new(2026, 11, 10),
                                  amount: 100_000)
    assert_not result.taxed?
    assert_equal 0.to_d, result.gmf_amount
  end

  test "calendar month reset: november starts fresh" do
    limit = Gmf::Uvt.exemption_limit(2026)
    Gmf::Calculator.call(user: @user, origin_money_source: @account,
                         operation_type: :expense_payment, date: Date.new(2026, 10, 31),
                         amount: limit)
    # November should have full exemption available again (no accumulator yet)
    acc = GmfMonthlyAccumulator.for(user: @user, money_source: @account, date: Date.new(2026, 11, 1))
    assert_equal 0.to_d, acc.covered_by_exemption
  end
end

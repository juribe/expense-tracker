require "test_helper"

class FinancialHabitsDetailTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Detail User", email: "habits_detail_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @category = Category.where(category_type: "expense").first
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true, starting_balance: 100_000_000)
  end

  def expense(amount, date:, description:)
    Expense.create!(user: @user, category: @category, money_source: @bank, amount: amount, date: date, description: description)
  end

  test "builds merchant detail with ranking and related movements" do
    4.times { |i| expense(-12_000, date: Date.current.beginning_of_month + i.days, description: "Café") }

    result = FinancialHabits::Detail.new(user: @user, key: "merchant_frequency").call

    assert_equal :ok, result[:state]
    assert_equal "ranking", result[:detail][:visualization][:type]
    assert result[:detail][:related_movements].any?
  end

  test "returns not_found for an unknown analysis" do
    result = FinancialHabits::Detail.new(user: @user, key: "unknown").call

    assert_equal :not_found, result[:state]
  end
end
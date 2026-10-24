# frozen_string_literal: true

require "test_helper"

class CategoryInsightTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "CI User", email: "ci_svc@example.com", password: "password123")
    @other = User.create!(name: "Other", email: "ci_other@example.com", password: "password123")
    @category = Category.create!(name: "Insight Svc Cat", is_default: true, category_type: "expense", suggested_savings_percentage: 15)
    @bank = @user.money_sources.create!(name: "Bank", kind: "account", active: true, starting_balance: 1_000_000_000)
    @loan = @user.money_sources.create!(name: "Loan", kind: "loan", active: true)
    @other_bank = @other.money_sources.create!(name: "Other Bank", kind: "account", active: true,
                                               starting_balance: 1_000_000_000)
    @anchor = Date.current
  end

  def expense(amount, date:, user: @user, category: @category, money_source: @bank)
    Expense.create!(user: user, category: category, money_source: money_source, amount: amount, date: date,
                    description: "x")
  end

  def insight
    CategoryInsight.new(user: @user, category: @category, date: @anchor).call
  end

  test "calculates average and estimated savings from completed cycles" do
    expense(-100_000, date: @anchor.prev_month)
    expense(-200_000, date: @anchor.prev_month.prev_month)
    expense(-300_000, date: @anchor.prev_month.prev_month.prev_month)

    data = insight
    assert_equal 200_000.to_d, data[:average_spending]
    assert_equal 30_000.to_d, data[:estimated_savings]
  end

  test "excludes current cycle from history" do
    expense(-500_000, date: @anchor)
    data = insight
    assert_nil data[:average_spending]
    assert_nil data[:estimated_savings]
  end

  test "excludes debt payments" do
    installment = expense(-200_000, date: @anchor.prev_month)
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 200_000, principal_amount: 200_000)
    data = insight
    assert_nil data[:average_spending]
  end

  test "user isolation" do
    expense(-100_000, date: @anchor.prev_month, user: @other, money_source: @other_bank)
    data = insight
    assert_nil data[:average_spending]
  end

  test "zero rate yields no estimate" do
    @category.update!(suggested_savings_percentage: 0)
    expense(-100_000, date: @anchor.prev_month)
    data = insight
    assert_equal 100_000.to_d, data[:average_spending]
    assert_nil data[:estimated_savings]
  end

  test "insufficient history shows tips" do
    @category.saving_tips.create!(title: "Tip", body: "Body", active: true, position: 0)
    data = insight
    assert_equal 1, data[:tips].size
  end
end

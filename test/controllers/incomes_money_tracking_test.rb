# frozen_string_literal: true

require "test_helper"

class IncomesMoneyTrackingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @category = Category.create!(name: "Salario simple", is_default: true, category_type: "income")
  end

  test "simple mode hides the money source selector on the income form" do
    user = simple_user
    sign_in user

    get new_income_path

    assert_response :success
    assert_select "select[name='income[money_source_id]']", count: 0
    assert_select "[data-testid=income-category-picker]"
    refute_includes response.body, "¿A dónde entra?"
  end

  test "simple mode creates an income on General without a source selection" do
    user = simple_user
    general = user.general_money_source
    sign_in user

    assert_difference "Income.count", 1 do
      post incomes_path, params: {
        income: {
          amount: "1500000",
          description: "Salario",
          date: Date.current.to_s,
          category_id: @category.id
        }
      }
    end

    assert_redirected_to incomes_path
    income = Income.order(:created_at).last
    assert_equal general.id, income.money_source_id
    assert_equal BigDecimal("1500000"), general.reload.balance
  end

  test "simple mode hides the money source column" do
    user = simple_user
    sign_in user
    user.incomes.create!(amount: 1_000_000, date: Date.current, category: @category,
                         description: "Salario", money_source: user.general_money_source)

    get incomes_path

    assert_response :success
    assert_select "th", text: "Fuente", count: 0
    assert_select "[data-testid=money-source]", count: 0
  end

  test "advanced mode keeps the source selector and uses the selected source" do
    user = detailed_user
    account = user.money_sources.create!(name: "Cuenta nómina", kind: "account")
    sign_in user

    get new_income_path

    assert_response :success
    assert_select "select[name='income[money_source_id]'] option", text: /Cuenta nómina/

    assert_difference "Income.count", 1 do
      post incomes_path, params: {
        income: {
          amount: "1500000",
          description: "Salario",
          date: Date.current.to_s,
          category_id: @category.id,
          money_source_id: account.id
        }
      }
    end

    assert_equal account.id, Income.order(:created_at).last.money_source_id
    assert_equal BigDecimal("1500000"), account.reload.balance
  end

  private

  def simple_user
    user = User.create!(name: "Simple Income", email: "simple_income_#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    user.ensure_general_money_source!
    user
  end

  def detailed_user
    User.create!(name: "Advanced Income", email: "advanced_income_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end

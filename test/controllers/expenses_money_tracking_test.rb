# frozen_string_literal: true

require "test_helper"

class ExpensesMoneyTrackingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @category = Category.create!(name: "Almuerzo simple", is_default: true, category_type: "expense")
  end

  test "simple mode hides the money source selector on the expense form" do
    user = simple_user
    sign_in user

    get new_expense_path

    assert_response :success
    assert_select "select[name='expense[money_source_id]']", count: 0
    assert_select "[data-testid=expense-category-picker]"
    refute_includes response.body, "¿Con qué se pagó?"
  end

  test "simple mode creates a manual expense on General even above its balance" do
    user = simple_user
    general = user.general_money_source
    assert_equal BigDecimal("0"), general.balance
    sign_in user

    assert_difference "Expense.count", 1 do
      post expenses_path, params: {
        expense: {
          amount: "30000",
          description: "Almuerzo",
          date: Date.current.to_s,
          category_id: @category.id
        }
      }
    end

    assert_redirected_to expenses_path
    expense = Expense.order(:created_at).last
    assert_equal general.id, expense.money_source_id
    assert_equal BigDecimal("-30000"), general.reload.balance
  end

  test "simple mode hides the source column, filter and bulk source action" do
    user = simple_user
    sign_in user
    user.expenses.create!(amount: 10_000, date: Date.current, category: @category,
                          description: "Almuerzo", money_source: user.general_money_source)

    get expenses_path

    assert_response :success
    assert_select "select[name='money_source_id']", count: 0
    assert_select "#bulkSource", count: 0
    assert_select "th", text: "Fuente", count: 0
  end

  test "simple mode hides the money source from the expense drawer" do
    user = simple_user
    sign_in user
    expense = user.expenses.create!(amount: 10_000, date: Date.current, category: @category,
                                    description: "Almuerzo", money_source: user.general_money_source)

    get expense_path(expense)

    assert_response :success
    assert_select ".drawer-label", text: "Fuente", count: 0
    refute_includes response.body, user.general_money_source.display_name
  end

  test "advanced mode keeps the money source selector and the explicit source" do
    user = detailed_user
    account = user.money_sources.create!(name: "Cuenta principal", kind: "account", starting_balance: 1_000_000)
    sign_in user

    get new_expense_path

    assert_response :success
    assert_select "select[name='expense[money_source_id]'] option", text: /Cuenta principal/

    assert_difference "Expense.count", 1 do
      post expenses_path, params: {
        expense: {
          amount: "30000",
          description: "Almuerzo",
          date: Date.current.to_s,
          category_id: @category.id,
          money_source_id: account.id
        }
      }
    end

    assert_equal account.id, Expense.order(:created_at).last.money_source_id
  end

  test "advanced mode still rejects a manual expense above the source balance" do
    user = detailed_user
    account = user.money_sources.create!(name: "Cuenta sin saldo", kind: "account", starting_balance: 10_000)
    sign_in user

    assert_no_difference "Expense.count" do
      post expenses_path, params: {
        expense: {
          amount: "30000",
          description: "Almuerzo",
          date: Date.current.to_s,
          category_id: @category.id,
          money_source_id: account.id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/saldo/i, response.body)
    assert_equal BigDecimal("10000"), account.reload.balance
  end

  test "advanced mode keeps the bulk source edit available" do
    user = detailed_user
    original_account = user.money_sources.create!(name: "Cuenta anterior", kind: "account",
                                                  starting_balance: 1_000_000)
    account = user.money_sources.create!(name: "Cuenta principal", kind: "account", starting_balance: 1_000_000)
    expense = user.expenses.create!(amount: 10_000, date: Date.current, category: @category,
                                    description: "Almuerzo", money_source: original_account)
    sign_in user

    get expenses_path

    assert_response :success
    assert_select "#bulkSource"
    assert_select "select[name='money_source_id']"

    patch bulk_update_expenses_path, params: { expense_ids: [ expense.id ], money_source_id: account.id }

    assert_redirected_to expenses_path
    assert_equal account.id, expense.reload.money_source_id
    assert_equal @category.id, expense.category_id
    assert_equal Date.current, expense.date
  end

  private

  def simple_user
    user = User.create!(name: "Simple Expenses", email: "simple_expenses_#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    user.ensure_general_money_source!
    user
  end

  def detailed_user
    User.create!(name: "Advanced Expenses", email: "advanced_expenses_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end

# frozen_string_literal: true

require "test_helper"

class ExpensesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "expenses_index_test@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Food", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Transport", is_default: true, category_type: "expense")
    sign_in @user
  end

  def create_expense(amount:, date:, category: @category, description: "Lunch")
    @user.expenses.create!(amount: amount, date: date, category: category, description: description)
  end

  test "GET /expenses renders the table with expenses" do
    create_expense(amount: 12.50, date: Date.today)
    get expenses_path
    assert_response :success
    assert_select "[data-testid=table]"
    assert_select "tr[data-testid=row]", count: 1
    assert_select "form[data-testid=filter-form]"
    assert_select "#resultsMeta", text: /1 expense/
  end

  test "GET /expenses shows empty state when no expenses exist" do
    get expenses_path
    assert_response :success
    assert_select "[data-testid=empty]"
    assert_select "h2", text: "No expenses yet"
    assert_select "table", count: 0
  end

  test "GET /expenses shows no-results state when filters match nothing" do
    create_expense(amount: 12.50, date: Date.today)
    get expenses_path, params: { category_id: @other_category.id }
    assert_response :success
    assert_select "[data-testid=empty]"
    assert_select "h2", text: "No expenses match these filters"
  end

  test "GET /expenses filters by category with a row-level where filter" do
    create_expense(amount: 12.50, date: Date.today, category: @category)
    create_expense(amount: 9.00, date: Date.today, category: @other_category, description: "Bus")
    get expenses_path, params: { category_id: @category.id }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 1
    assert_select "td", text: "Lunch"
    assert_no_match(/Bus/, response.body)
  end

  test "GET /expenses filters by amount range" do
    create_expense(amount: 10.00, date: Date.today, description: "Low")
    create_expense(amount: 50.00, date: Date.today, description: "Mid")
    create_expense(amount: 100.00, date: Date.today, description: "High")
    get expenses_path, params: { min_amount: "20", max_amount: "75" }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 1
    assert_select "td", text: "Mid"
  end

  test "GET /expenses filters by date range" do
    create_expense(amount: 10.00, date: Date.new(2026, 1, 10), description: "Old")
    create_expense(amount: 20.00, date: Date.new(2026, 3, 15), description: "Rent")
    get expenses_path, params: { start_date: "2026-03-01", end_date: "2026-03-31" }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 1
    assert_select "td", text: "Rent"
  end

  test "GET /expenses validates min > max amount and does not run the query" do
    create_expense(amount: 50.00, date: Date.today)
    get expenses_path, params: { min_amount: "100", max_amount: "10" }
    assert_response :success
    assert_select "input.is-invalid"
    assert_select "tr[data-testid=row]", count: 0
  end

  test "GET /expenses validates start date after end date" do
    get expenses_path, params: { start_date: "2026-04-01", end_date: "2026-03-01" }
    assert_response :success
    assert_select "input.is-invalid"
    assert_select "div.alert-danger", text: /Fix the highlighted filter fields/
  end

  test "GET /expenses sorts by amount ascending" do
    create_expense(amount: 10.00, date: Date.today, description: "Low")
    create_expense(amount: 99.00, date: Date.today, description: "High")
    get expenses_path, params: { sort: "amount", dir: "asc" }
    assert_response :success
    assert_select "thead th[aria-sort=ascending]"
    body = response.body
    assert body.index("Low") < body.index("High"), "expected amount ascending order"
  end

  test "GET /expenses defaults to date descending sort" do
    create_expense(amount: 10.00, date: Date.new(2026, 1, 1), description: "Old")
    create_expense(amount: 20.00, date: Date.new(2026, 5, 1), description: "New")
    get expenses_path
    assert_response :success
    assert_select "thead th[aria-sort=descending]"
    body = response.body
    assert body.index("New") < body.index("Old"), "expected date descending order"
  end

  test "GET /expenses paginates at 25 rows and preserves page param" do
    30.times { |i| create_expense(amount: i + 1, date: Date.today, description: "Expense #{i}") }
    get expenses_path, params: { page: 1 }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 25
    assert_select "nav[data-testid=pagination]"
    get expenses_path, params: { page: 2 }
    assert_select "tr[data-testid=row]", count: 5
  end

  test "GET /expenses shows the subtotal of the visible page, not the filtered total" do
    30.times { |i| create_expense(amount: 10.0 + i, date: Date.today, description: "Expense #{i}") }
    get expenses_path, params: { page: 2 }
    assert_response :success
    assert_select "#pageFoot", text: /Page total -\$60\.00/
    assert_select "#pageFoot", text: /Filtered total -\$735\.00/
  end

  test "GET /expenses.csv exports the filtered set as CSV" do
    create_expense(amount: 12.50, date: Date.new(2026, 3, 10), description: 'Lunch, "business"')
    create_expense(amount: 8.00, date: Date.new(2026, 1, 1), description: "Excluded", category: @other_category)
    get expenses_path(format: :csv), params: { category_id: @category.id }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "date,description,category,amount"
    assert_includes response.body, '2026-03-10,"Lunch, ""business""",Food,-12.5'
    assert_includes response.body, "Food"
    refute_includes response.body, "Excluded"
  end

  test "GET /expenses/:id renders the drawer fragment" do
    expense = create_expense(amount: 12.50, date: Date.today)
    get expense_path(expense)
    assert_response :success
    assert_select "dl.drawer-dl"
    assert_select "dt", text: "Amount"
  end

  test "DELETE /expenses/:id destroys and preserves filter query" do
    expense = create_expense(amount: 12.50, date: Date.today)
    delete expense_path(expense), params: { category_id: @category.id, sort: "amount", dir: "asc" }
    assert_redirected_to expenses_path(category_id: @category.id.to_s, sort: "amount", dir: "asc")
    assert_not Expense.exists?(expense.id)
    follow_redirect!
    assert_equal "Expense was successfully deleted.", flash[:notice]
  end

  test "DELETE /expenses/bulk_destroy removes selected expenses" do
    a = create_expense(amount: 1, date: Date.today, description: "A")
    b = create_expense(amount: 2, date: Date.today, description: "B")
    c = create_expense(amount: 3, date: Date.today, description: "C")
    delete bulk_destroy_expenses_path, params: { ids: [ a.id, c.id ] }
    assert_redirected_to expenses_path
    assert Expense.exists?(b.id)
    assert_not Expense.exists?(a.id)
    assert_not Expense.exists?(c.id)
  end

  test "DELETE /expenses/bulk_destroy with no ids redirects with alert" do
    delete bulk_destroy_expenses_path, params: { ids: [] }
    assert_redirected_to expenses_path
    follow_redirect!
    assert_equal "No expenses selected.", flash[:alert]
  end
end

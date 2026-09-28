# frozen_string_literal: true

require "test_helper"

# Walks every sidebar entry point with seeded data so Bullet (raise mode,
# see test_helper BulletIntegrationHook) flags N+1 queries per page.
class SidebarIndexesBulletTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Test User", email: "sidebar_bullet_test@example.com", password: "password123")
    sign_in @user

    @categories = 3.times.map do |i|
      Category.create!(name: "Cat #{i}", is_default: true, category_type: "expense")
    end
    income_category = Category.create!(name: "Salary", is_default: true, category_type: "income")

    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0, bank: "Bancolombia")
    card.build_credit_account(credit_limit: 2_000_000, card_brand: "visa", card_last_four: "1234").save!
    recognition = MoneySourceRecognition.create!(money_source: card)
    recognition.recognition_identifiers.create!(kind: "keyword", value: "visa-banco", status: "confirmed", origin: "user")
    recognition.recognition_identifiers.create!(kind: "sender", value: "notificaciones@bancolombia.com", status: "confirmed", origin: "user")
    account = @user.money_sources.create!(name: "Nequi", kind: "account", starting_balance: 1000)
    account2 = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 500)
    loan = @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle", starting_balance: 0)
    cash_recognition = MoneySourceRecognition.create!(money_source: account2)
    cash_recognition.recognition_identifiers.create!(kind: "keyword", value: "efectivo", status: "confirmed", origin: "user")
    account2.update!(parent_id: account.id)

    @categories.each do |category|
      @user.expenses.create!(amount: 50_000, date: Date.current, category: category, money_source: card)
      @user.incomes.create!(amount: 1_000_000, date: Date.current, category: category)
      @user.budgets.create!(category: category, monthly_amount: 200_000, period: "monthly")
      @user.spending_alerts.create!(category: category, kind: "budget_threshold", month: Date.current.strftime("%Y-%m"), pct: 85, amount: 150_000)
      @user.transaction_rules.create!(name: "Rule #{category.name}", merchant_contains: category.name, category_id: category.id)
    end
    @user.transaction_rules.create!(name: "Rule source condition", money_source_condition_id: card.id, category_id: @categories[0].id)
    @user.transaction_rules.create!(name: "Rule money source action", merchant_contains: "starbucks", action_money_source_id: card.id)

    @user.expense_candidates.create!(amount: 30_000, date: Date.current, source: "text", money_source: card)
    @user.expense_candidates.create!(amount: 40_000, date: Date.current, source: "text", money_source: card)

    3.times { |i| @user.recurring_templates.create!(category: @categories[i], kind: i.zero? ? "income" : "expense", amount: 10_000 * (i + 1), frequency: "monthly", source: "wizard", description: "Recurring #{i}") }
    @user.transactions.create!(category: @categories[0], date: Date.current.beginning_of_month, amount: 10_000, kind: "expense", source: "manual", recurring_template_id: @user.recurring_templates.second.id, description: "Recurring 1")
    @user.transactions.create!(category: @categories[0], date: Date.current, amount: 5_000, kind: "expense", source: "manual", money_source: account, description: "Nequi gasto")
    @user.transactions.create!(category: @categories[1], date: Date.current, amount: 8_000, kind: "expense", source: "manual", money_source: account, description: "Nequi gasto 2")
    @user.transactions.create!(category: @categories[1], date: Date.current, amount: 3_000, kind: "expense", source: "manual", money_source: account2, description: "Efectivo gasto")

    Transfer.create!(user: @user, from_source: account, to_source: card, amount: 20_000, date: Date.current)
    Transfer.create!(user: @user, from_source: account, to_source: loan, amount: 30_000, date: Date.current)
  end

  test "dashboard has no N+1" do
    get dashboard_path
    assert_response :success
  end

  test "expenses index has no N+1" do
    get expenses_path
    assert_response :success
  end

  test "incomes index has no N+1" do
    get incomes_path
    assert_response :success
  end

  test "categories index has no N+1" do
    get categories_path
    assert_response :success
  end

  test "budgets index has no N+1" do
    get budgets_path
    assert_response :success
  end

  test "alerts index has no N+1" do
    get alerts_path
    assert_response :success
  end

  test "expense_candidates index has no N+1" do
    get expense_candidates_path
    assert_response :success
  end

  test "expense_evaluations index has no N+1" do
    get expense_evaluations_path
    assert_response :success
  end

  test "expense_playground has no N+1" do
    get expense_playground_path
    assert_response :success
  end

  test "money_sources cash index has no N+1" do
    get money_sources_cash_path
    assert_response :success
  end

  test "money_sources credit_cards index has no N+1" do
    get money_sources_credit_cards_path
    assert_response :success
  end

  test "money_sources loans index has no N+1" do
    get money_sources_loans_path
    assert_response :success
  end

  test "money_sources recognition has no N+1" do
    get money_sources_recognition_path
    assert_response :success
  end

  test "monthly_expenses index has no N+1" do
    get monthly_expenses_path
    assert_response :success
  end

  test "monthly_incomes index has no N+1" do
    get monthly_incomes_path
    assert_response :success
  end

  test "monthly_reports index has no N+1" do
    get monthly_reports_path
    assert_response :success
  end

  test "transaction_rules index has no N+1" do
    get transaction_rules_path
    assert_response :success
  end

  test "transfers index has no N+1" do
    get transfers_path
    assert_response :success
  end

  test "whatsapp settings has no N+1" do
    get whatsapp_settings_path
    assert_response :success
  end

  test "financial_setup has no N+1" do
    get financial_setup_path
    assert_response :success
  end

  test "gmail settings has no N+1" do
    get gmail_connection_path
    assert_response :success
  end
end

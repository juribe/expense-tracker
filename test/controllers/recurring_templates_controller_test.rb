# frozen_string_literal: true

require "test_helper"

class RecurringTemplatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Recurring Ctrl User",
      email: "recurring_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account")
    @card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card")
    @loan = @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")
  end

  test "GET /recurring_templates (income) offers only payment sources" do
    get recurring_templates_path(kind: "income")
    assert_response :success

    offered = @user.money_sources.active.payment_sources.to_a.map(&:id)
    assert_select "select[name='recurring_template[money_source_id]'] option" do |options|
      values = options.map { |o| o["value"] }
      offered.each { |id| assert_includes values, id.to_s }
      assert_not_includes values, @loan.id.to_s
    end
  end

  test "GET /recurring_templates (expense) keeps loans for debt-payment cuotas" do
    get recurring_templates_path(kind: "expense")
    assert_response :success

    assert_select "select[name='recurring_template[money_source_id]'] option" do |options|
      values = options.map { |o| o["value"] }
      assert_includes values, @account.id.to_s
      assert_includes values, @card.id.to_s
      # The wizard-backed debt-payment cuota points at the loan itself.
      assert_includes values, @loan.id.to_s
    end
  end

  test "the pay/receive modal offers only payment sources and a template default" do
    get recurring_templates_path(kind: "expense")
    assert_response :success

    assert_select "#processModal #processMoneySource option" do |options|
      texts = options.map(&:text)
      values = options.map { |o| o["value"] }
      assert_includes values, ""
      assert_includes values, @account.id.to_s
      assert_includes values, @card.id.to_s
      assert_not texts.any? { |t| t.include?("Crédito Vehículo") }
    end
  end

  test "GET /recurring_templates (income) offers only income categories" do
    income = Category.create!(name: "Salario Recurrente", is_default: false, category_type: "income", user: @user)
    expense = Category.create!(name: "Servicios Recurrente", is_default: false, category_type: "expense", user: @user)

    get recurring_templates_path(kind: "income")

    assert_response :success
    assert_select "[data-testid=recurring-template-category-picker] [role=option][data-value=?]", income.id.to_s
    assert_select "[data-testid=recurring-template-category-picker] [role=option][data-value=?]", expense.id.to_s, count: 0
  end

  test "GET /recurring_templates (expense) offers only expense categories" do
    income = Category.create!(name: "Salario Recurrente", is_default: false, category_type: "income", user: @user)
    expense = Category.create!(name: "Servicios Recurrente", is_default: false, category_type: "expense", user: @user)

    get recurring_templates_path(kind: "expense")

    assert_response :success
    assert_select "[data-testid=recurring-template-category-picker] [role=option][data-value=?]", expense.id.to_s
    assert_select "[data-testid=recurring-template-category-picker] [role=option][data-value=?]", income.id.to_s, count: 0
  end

  test "POST process_transaction records the payment with the chosen money source" do
    template = @user.recurring_templates.create!(
      category: @category || Category.create!(name: "Recurring Ctrl Cat", is_default: false, category_type: "expense", user: @user),
      kind: "expense", amount: 65_000, frequency: "monthly", source: "wizard", description: "Cuota"
    )
    post process_transaction_recurring_template_path(template), params: {
      amount: "65000", date: Date.current.to_s, money_source_id: @account.id
    }

    assert_redirected_to recurring_templates_path(kind: "expense")
    transaction = template.transactions.last
    assert_equal @account.id, transaction.money_source_id
  end

  test "POST process_transaction without an explicit source falls back to the template's source" do    template = @user.recurring_templates.create!(
      category: Category.create!(name: "Recurring Fallback Cat", is_default: false, category_type: "expense", user: @user),
      kind: "expense", amount: 65_000, frequency: "monthly", source: "wizard", description: "Cuota",
      money_source: @loan
    )
    post process_transaction_recurring_template_path(template), params: {
      amount: "65000", date: Date.current.to_s
    }

    assert_redirected_to recurring_templates_path(kind: "expense")
    assert_equal @loan.id, template.transactions.last.money_source_id
  end

  test "POST process_transaction rejects a non-payment or foreign money source" do
    @loan # payment sources only: a loan id must be rejected
    template = @user.recurring_templates.create!(
      category: Category.create!(name: "Recurring Invalid Cat", is_default: false, category_type: "expense", user: @user),
      kind: "expense", amount: 65_000, frequency: "monthly", source: "wizard", description: "Cuota"
    )
    foreign = User.create!(name: "F", email: "foreign_rt#{SecureRandom.hex(4)}@example.com", password: "password123")
    foreign_account = foreign.money_sources.create!(name: "Cuenta Ajena", kind: "account")

    [ [ "loan-id", @loan.id ], [ "foreign", foreign_account.id ] ].each do |(_label, source_id)|
      assert_no_difference "Transaction.count" do
        post process_transaction_recurring_template_path(template), params: {
          amount: "65000", date: Date.current.to_s, money_source_id: source_id
        }
      end
      assert_redirected_to recurring_templates_path(kind: "expense")
      assert_equal I18n.t("recurring.invalid_payment_source"), flash[:alert]
      assert template.transactions.empty?
    end
  end

  test "POST process_transaction rejects an expense template left without any money source" do
    template = @user.recurring_templates.create!(
      category: Category.create!(name: "Recurring Unlinked Cat", is_default: false, category_type: "expense", user: @user),
      kind: "expense", amount: 65_000, frequency: "monthly", source: "manual", description: "Recordatorio"
    )
    assert_nil template.money_source

    assert_no_difference "Transaction.count" do
      post process_transaction_recurring_template_path(template), params: {
        amount: "65000", date: Date.current.to_s
      }
    end

    assert_response :see_other
    assert_equal I18n.t("recurring.missing_money_source"), flash[:alert]
    assert template.transactions.empty?
  end

  test "POST process_transaction keeps rejecting an income template left without any money source" do
    template = @user.recurring_templates.create!(
      category: Category.create!(name: "Recurring Income Cat", is_default: false, category_type: "income", user: @user),
      kind: "income", amount: 200_000, frequency: "monthly", source: "manual", description: "Recibo"
    )
    assert_nil template.money_source

    assert_no_difference "Transaction.count" do
      post process_transaction_recurring_template_path(template), params: {
        amount: "200000", date: Date.current.to_s
      }
    end

    assert_response :see_other
    assert template.transactions.empty?
  end

  test "POST /recurring_templates rejects a foreign money source" do
    other_user = User.create!(name: "Other", email: "recurring_foreign_source@example.com", password: "password123")
    foreign_account = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account")
    category = Category.create!(name: "Servicios Ctrl", is_default: false, category_type: "expense", user: @user)

    assert_no_difference "RecurringTemplate.count" do
      post recurring_templates_path, params: {
        recurring_template: { category_id: category.id, kind: "expense", amount: 65_000,
                              description: "Cuota", payment_day: 5, money_source_id: foreign_account.id }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST /recurring_templates rejects a foreign category" do
    other_user = User.create!(name: "Other", email: "recurring_foreign_category@example.com", password: "password123")
    foreign_category = Category.create!(name: "Ajena Ctrl", is_default: false, category_type: "expense",
                                        user: other_user)

    assert_no_difference "RecurringTemplate.count" do
      post recurring_templates_path, params: {
        recurring_template: { category_id: foreign_category.id, kind: "expense", amount: 65_000,
                              description: "Cuota", payment_day: 5 }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST /recurring_templates accepts a shared category with an own money source" do
    category = Category.create!(name: "Cuota Ctrl", is_default: true, category_type: "expense")

    assert_difference "RecurringTemplate.count", 1 do
      post recurring_templates_path, params: {
        recurring_template: { category_id: category.id, kind: "expense", amount: 50_000,
                              description: "Cuota", payment_day: 5, money_source_id: @account.id }
      }
    end

    assert_redirected_to recurring_templates_path(kind: "expense")
    assert_equal category, RecurringTemplate.last.category
    assert_equal @account, RecurringTemplate.last.money_source
  end
end

# frozen_string_literal: true

require "test_helper"

class ExpensesAiEntryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PremiumAccessTestHelper

  setup do
    @user = User.create!(name: "AI Entry User", email: "ai-entry@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    @parking = Category.create!(name: "Parking", is_default: true, category_type: "expense")
    @source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 10_000_000)
    sign_in @user
    @saved_api_key = ENV.delete("MISTRAL_API_KEY")
  end

  teardown do
    ENV["MISTRAL_API_KEY"] = @saved_api_key
  end

  test "POST /expenses/parse requires authentication" do
    sign_out :user
    post parse_expenses_path, params: { text: "50 mil en almuerzo" }
    assert_response :redirect
  end

  test "POST /expenses/parse returns structured expenses without persisting anything" do
    assert_no_difference -> { Expense.count } do
      assert_no_difference -> { Category.count } do
        post parse_expenses_path(format: :json),
             params: { text: "Me gasté 50 mil en un restaurante y 20 mil en parqueadero" }
      end
    end

    assert_response :success
    data = JSON.parse(response.body)

    assert_equal "Me gasté 50 mil en un restaurante y 20 mil en parqueadero", data["transcription"]
    assert_equal 2, data["expenses"].length

    first = data["expenses"].first
    assert_equal 50_000.0, first["amount"]
    assert_equal @restaurants.id, first["category_id"]
    assert_equal "Restaurants", first["category_name"]
    assert_equal false, first["create_category"]
    assert_equal Date.current.iso8601, first["transaction_date"]
    assert first.key?("confidence")
  end

  test "POST /expenses/parse suggests a new category without creating anything during preview" do
    stub_method(ExpenseResolver::NaturalLanguageParser, :call, ->(**_kwargs) {
      ServiceResult.success([ Ai::Tasks::ParsedExpense.new(
        original_text: "gasté 30 mil en la veterinaria del perro",
        amount: 30_000, date: Date.current, description: "Veterinaria del perro",
        category: "Pet Care", money_source_hint: nil, confidence: 0.9
      ) ])
    }) do
      post parse_expenses_path(format: :json), params: { text: "gasté 30 mil en la veterinaria del perro" }
    end

    assert_response :success
    expense = JSON.parse(response.body)["expenses"].first

    assert_nil expense["category_id"]
    assert_equal true, expense["create_category"]
    assert_equal "Pet Care", expense["category_name"]

    # Parsing never creates categories: the suggestion is only shown on confirm.
    assert_equal 2, Category.count
  end

  test "POST /expenses/parse rejects blank text" do
    post parse_expenses_path(format: :json), params: { text: "" }

    assert_response :unprocessable_entity
    errors = JSON.parse(response.body)["errors"]
    assert errors.any?
  end

  test "POST /expenses/parse reports when no expenses are detected" do
    post parse_expenses_path(format: :json), params: { text: "hola que tal" }

    assert_response :unprocessable_entity
    assert_empty JSON.parse(response.body)["expenses"]
  end

  test "POST /expenses/bulk_create saves several expenses in one action" do
    post bulk_create_expenses_path(format: :json), params: {
      expenses: [
        { amount: "50000", description: "Restaurante", transaction_date: "2026-08-22", category_id: @restaurants.id,
          money_source_id: @source.id },
        { amount: "20000", description: "Parqueadero", date: "2026-08-21", category_id: @parking.id,
          money_source_id: @source.id }
      ]
    }

    assert_response :created
    data = JSON.parse(response.body)
    assert_equal 2, data["created"]
    assert_equal expenses_url, data["redirect_to"]

    saved = @user.expenses.order(:description)
    assert_equal 2, saved.count

    restaurante = saved.find_by(description: "Restaurante")
    assert_equal BigDecimal("-50000"), restaurante.amount
    assert_equal @restaurants.id, restaurante.category_id
    assert_equal Date.new(2026, 8, 22), restaurante.date
    assert_equal "ai", restaurante.source

    parqueadero = saved.find_by(description: "Parqueadero")
    assert_equal BigDecimal("-20000"), parqueadero.amount
    assert_equal Date.new(2026, 8, 21), parqueadero.date
  end

  test "POST /expenses/bulk_create persists the selected money source" do
    source = @user.money_sources.create!(name: "Nequi", kind: "wallet")

    post bulk_create_expenses_path(format: :json), params: {
      expenses: [
        { amount: "50000", description: "Almuerzo", transaction_date: "2026-08-22",
          category_id: @restaurants.id, money_source_id: source.id }
      ]
    }

    assert_response :created
    expense = @user.expenses.sole
    assert_equal source, expense.money_source
  end

  test "POST /expenses/bulk_create creates missing categories by name" do
    assert_difference -> { Category.count }, +1 do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "30000", description: "Veterinaria", new_category_name: "Pet Care",
            transaction_date: Date.current.iso8601, money_source_id: @source.id }
        ]
      }
    end

    assert_response :created
    pet_care = Category.find_by!(name: "Pet Care")
    expense = @user.expenses.sole
    assert_equal pet_care.id, expense.category_id
  end

  test "POST /expenses/bulk_create skips the suggested category when a rule matches" do
    TransactionRule.create!(user: @user, merchant_contains: nil,
                            description_contains: "didi", category_id: @restaurants.id)

    assert_no_difference -> { Category.count } do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "50000", description: "Didi viaje", transaction_date: Date.current.iso8601,
            new_category_name: "Didi Tarjeta Visa Infinite", money_source_id: @source.id }
        ]
      }
    end

    assert_response :created
    assert_nil Category.find_by(name: "Didi Tarjeta Visa Infinite")
    expense = @user.expenses.sole
    assert_equal @restaurants.id, expense.category_id
    assert_includes expense.applied_rule_ids, TransactionRule.last.id
  end

  test "POST /expenses/bulk_create keeps the category the user explicitly picked" do
    TransactionRule.create!(user: @user, merchant_contains: nil,
                            description_contains: "didi", category_id: @restaurants.id)

    post bulk_create_expenses_path(format: :json), params: {
      expenses: [
        { amount: "50000", description: "Didi viaje", transaction_date: Date.current.iso8601,
          category_id: @parking.id, category_edited: true, money_source_id: @source.id }
      ]
    }

    assert_response :created
    expense = @user.expenses.sole
    assert_equal @parking.id, expense.category_id
    assert_empty expense.applied_rule_ids
  end

  test "POST /expenses/bulk_create rolls everything back when a row is invalid" do
    assert_no_changes -> { Expense.count } do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "1000", description: "Ok", transaction_date: "2026-08-22", category_id: @parking.id,
            money_source_id: @source.id },
          { amount: "", description: "Bad", category_id: @parking.id, money_source_id: @source.id }
        ]
      }
    end

    assert_response :unprocessable_entity
    errors = JSON.parse(response.body)["errors"]
    row_label = I18n.t("expenses.bulk_row_error", index: 2, message: "[MSG]").split("[MSG]").first
    assert errors.first.to_s.include?(row_label)
  end

  test "POST /expenses/bulk_create redirects HTML requests back to the list" do
    post bulk_create_expenses_path, params: {
      expenses: [
        { amount: "50000", description: "Almuerzo", transaction_date: Date.current.iso8601,
          category_id: @restaurants.id, money_source_id: @source.id }
      ]
    }

    assert_redirected_to expenses_path
    follow_redirect!
    assert_equal I18n.t("expenses.bulk_created", count: 1, default: "1 gasto creado."), flash[:notice]
  end

  test "users without premium see the expense assistant locked" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    revoke_premium(@user)
    sign_in @user

    get expenses_path

    assert_response :success
    assert_select "[data-testid='ai-entry-card']" do
      assert_select ".ai-entry-premium", text: /PREMIUM/
      assert_select "textarea#aiExpenseText[disabled]"
      assert_select "button#aiMicButton[disabled]"
      assert_select "button#aiParseButton[disabled]"
      assert_select "button[data-ai-example][disabled]", count: 3
    end
  end

  test "the locked expense assistant offers the premium upgrade panel" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    revoke_premium(@user)
    sign_in @user

    get expenses_path

    assert_response :success
    assert_select "[data-testid='ai-entry-premium-lock']" do
      assert_select ".ai-entry-lock .ti-lock"
      assert_select "strong", text: "Desbloquea tu asistente con Premium"
      assert_select "a[href=?]", plans_path, text: /Conocer Premium/
    end
    assert_select "#aiPreviewModal", count: 0
  end

  test "premium users keep the expense assistant fully enabled" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    grant_premium(@user)
    sign_in @user

    get expenses_path

    assert_response :success
    assert_select "[data-testid='ai-entry-card']" do
      assert_select "textarea#aiExpenseText:not([disabled])"
      assert_select "button#aiMicButton:not([disabled])"
      assert_select "button#aiParseButton:not([disabled])"
      assert_select "[data-testid='ai-entry-premium-lock']", count: 0
    end
    assert_select "#aiPreviewModal", count: 1
  end

  test "the expense assistant stays enabled when paid access is not required" do
    sign_in @user

    get expenses_path

    assert_response :success
    assert_select "textarea#aiExpenseText:not([disabled])"
    assert_select "[data-testid='ai-entry-premium-lock']", count: 0
  end

  test "POST /expenses/parse denies users without premium" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    revoke_premium(@user)
    sign_in @user

    post parse_expenses_path(format: :json), params: { text: "50 mil en almuerzo" }

    assert_response :forbidden
    assert_equal I18n.t("errors.premium_only"), JSON.parse(response.body)["error"]
  end

  test "POST /expenses/bulk_create denies users without premium without persisting expenses" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    revoke_premium(@user)
    sign_in @user

    assert_no_difference -> { Expense.count } do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "50000", description: "Almuerzo", transaction_date: Date.current.iso8601,
            category_id: @restaurants.id, money_source_id: @source.id }
        ]
      }
    end

    assert_response :forbidden
    assert_equal I18n.t("errors.premium_only"), JSON.parse(response.body)["error"]
  end

  test "premium users keep using parse and bulk create" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    grant_premium(@user)
    sign_in @user

    post parse_expenses_path(format: :json),
         params: { text: "Me gasté 50 mil en un restaurante y 20 mil en parqueadero" }
    assert_response :success

    assert_difference -> { Expense.count }, +1 do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "50000", description: "Almuerzo", transaction_date: Date.current.iso8601,
            category_id: @restaurants.id, money_source_id: @source.id }
        ]
      }
    end
    assert_response :created
  end
end

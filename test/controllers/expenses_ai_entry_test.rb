# frozen_string_literal: true

require "test_helper"

class ExpensesAiEntryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "AI Entry User", email: "ai-entry@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants")
    sign_in @user
    @saved_api_key = ENV.delete("OPENAI_API_KEY")
  end

  teardown do
    ENV["OPENAI_API_KEY"] = @saved_api_key
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

  test "POST /expenses/parse suggests a new category without creating it" do
    post parse_expenses_path(format: :json), params: { text: "gasté 30 mil en la veterinaria del perro" }

    assert_response :success
    expense = JSON.parse(response.body)["expenses"].first

    assert_nil expense["category_id"]
    assert_equal true, expense["create_category"]
    assert_equal "Pet Care", expense["category_name"]

    # The suggestion must not create the category.
    assert_equal 1, Category.count
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
    parking = Category.create!(name: "Parking")

    post bulk_create_expenses_path(format: :json), params: {
      expenses: [
        { amount: "50000", description: "Restaurante", transaction_date: "2026-08-22", category_id: @restaurants.id },
        { amount: "20000", description: "Parqueadero", date: "2026-08-21", category_id: parking.id }
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

  test "POST /expenses/bulk_create creates missing categories by name" do
    assert_difference -> { Category.count }, +1 do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "30000", description: "Veterinaria", new_category_name: "Pet Care",
            transaction_date: Date.current.iso8601 }
        ]
      }
    end

    assert_response :created
    pet_care = Category.find_by!(name: "Pet Care")
    expense = @user.expenses.sole
    assert_equal pet_care.id, expense.category_id
  end

  test "POST /expenses/bulk_create rolls everything back when a row is invalid" do
    parking = Category.create!(name: "Parking")

    assert_no_changes -> { Expense.count } do
      post bulk_create_expenses_path(format: :json), params: {
        expenses: [
          { amount: "1000", description: "Ok", transaction_date: "2026-08-22", category_id: parking.id },
          { amount: "", description: "Bad", category_id: parking.id }
        ]
      }
    end

    assert_response :unprocessable_entity
    errors = JSON.parse(response.body)["errors"]
    assert errors.first.to_s.include?("Expense 2")
  end

  test "POST /expenses/bulk_create redirects HTML requests back to the list" do
    post bulk_create_expenses_path, params: {
      expenses: [
        { amount: "50000", description: "Almuerzo", transaction_date: Date.current.iso8601,
          category_id: @restaurants.id }
      ]
    }

    assert_redirected_to expenses_path
    follow_redirect!
    assert_equal "1 expense created.", flash[:notice]
  end
end

# frozen_string_literal: true

require "test_helper"

class MoneySourceStatementTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Stmt Ctrl", email: "stmt_ctrl@example.com", password: "password123")
    sign_in @user
    @source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1000)
  end

  test "GET show renders movements tab for supported source" do
    get money_source_path(@source)
    assert_response :success
    assert_select "[data-tab-slug='movimientos']"
  end

  test "GET extractos with period param activates movements and filters" do
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Gasto", source: "manual")
    get extractos_money_source_path(@source), params: { period: "7days", kind: "out", q: "Gasto" }
    assert_response :success
    assert_match(/Gasto/, response.body)
  end

  test "GET statement alias renders" do
    get statement_money_source_path(@source)
    assert_response :success
  end

  test "GET movements alias renders" do
    get movements_money_source_path(@source)
    assert_response :success
  end

  test "GET extracto alias renders" do
    get extracto_money_source_path(@source)
    assert_response :success
  end

  test "GET nested extractos route renders the statement" do
    get extractos_money_source_path(@source)
    assert_response :success
    assert_select "#movementRows"
  end

  test "debt source shows the movements tab and renders its extracto" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)

    get money_source_path(card)
    assert_response :success
    assert_select "[data-tab-slug='movimientos']"

    get extractos_money_source_path(card)
    assert_response :success
    assert_select "#movementRows"
  end

  test "debt extract uses payment and purchase terminology" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    @user.expenses.create!(money_source: card, amount: 100, date: Date.current,
                           description: "Compra", source: "manual")

    get extractos_money_source_path(card)

    assert_response :success
    assert_match(/Pagos/, response.body)
    assert_match(/Compras/, response.body)
    assert_match(/Compra/, response.body)
  end

  test "user cannot access another user's nested extractos route" do
    other = User.create!(name: "Other", email: "other_extractos_ctrl@example.com", password: "password123")
    other_source = other.money_sources.create!(name: "Otra", kind: "account")

    get extractos_money_source_path(other_source)

    assert_response :not_found
  end

  test "user cannot access other user statement" do
    other = User.create!(name: "Other", email: "other_stmt_ctrl@example.com", password: "password123")
    other_source = other.money_sources.create!(name: "Otra", kind: "account")
    get money_source_path(other_source)
    assert_response :not_found
  end
end

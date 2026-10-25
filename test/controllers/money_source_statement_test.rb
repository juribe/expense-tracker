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
    assert_select "#movementRows"
  end

  test "GET show with period param activates movements and filters" do
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Gasto", source: "manual")
    get money_source_path(@source), params: { period: "7days", kind: "out", q: "Gasto" }
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

  test "user cannot access other user statement" do
    other = User.create!(name: "Other", email: "other_stmt_ctrl@example.com", password: "password123")
    other_source = other.money_sources.create!(name: "Otra", kind: "account")
    get money_source_path(other_source)
    assert_response :not_found
  end
end
# frozen_string_literal: true

require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Alerts Controller User",
      email: "alerts_controller_test@example.com",
      password: "password123"
    )
    sign_in @user
    @category = Category.create!(
      name: "Restaurantes_#{SecureRandom.hex(4)}",
      category_type: "expense",
      user: @user
    )
    @current_month = Time.zone.today.strftime("%Y-%m")
    @threshold_alert = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 82, amount: 820_000)
    @increase_alert = SpendingAlert.create!(user: @user, category: @category, kind: "spending_increase", month: @current_month, pct: 38, amount: 500_000, previous_amount: 362_000)
    @read_alert = SpendingAlert.create!(user: @user, category: @category, kind: "budget_exceeded", month: @current_month, pct: 115, amount: 920_000, read_at: Time.current)
  end

  test "GET /alerts requires authentication" do
    sign_out @user
    get alerts_path
    assert_redirected_to new_user_session_path
  end

  test "GET /alerts renders the notification center with alerts" do
    get alerts_path
    assert_response :success
    assert_select "h1", /Alertas/
    assert_select "##{dom_id(@threshold_alert)}"
    assert_select "##{dom_id(@increase_alert)}"
  end

  test "GET /alerts shows the unread badge count" do
    get alerts_path
    assert_response :success
    assert_select "span.badge", text: "2"
  end

  test "GET /alerts shows the empty state for a user without alerts" do
    SpendingAlert.where(user: @user).destroy_all
    get alerts_path
    assert_response :success
    assert_select ".card", /Estás al día/
  end

  test "GET /alerts?filter=unread returns only unread alerts" do
    get alerts_path, params: { filter: "unread" }
    assert_response :success
    assert_select "##{dom_id(@threshold_alert)}"
    assert_select "##{dom_id(@increase_alert)}"
    assert_select "##{dom_id(@read_alert)}", count: 0
  end

  test "GET /alerts?filter=budget returns only budget alerts" do
    get alerts_path, params: { filter: "budget" }
    assert_response :success
    assert_select "##{dom_id(@threshold_alert)}"
    assert_select "##{dom_id(@read_alert)}"
    assert_select "##{dom_id(@increase_alert)}", count: 0
  end

  test "GET /alerts?filter=spending returns only spending alerts" do
    get alerts_path, params: { filter: "spending" }
    assert_response :success
    assert_select "##{dom_id(@increase_alert)}"
    assert_select "##{dom_id(@threshold_alert)}", count: 0
  end

  test "PATCH /alerts/:id marks the alert as read" do
    assert_not @threshold_alert.read?
    patch alert_path(@threshold_alert), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert @threshold_alert.reload.read?
  end

  test "PATCH /alerts/:id from a plain browser redirects to the center" do
    assert_not @threshold_alert.read?
    patch alert_path(@threshold_alert)

    assert_redirected_to alerts_path
    assert @threshold_alert.reload.read?
    follow_redirect!
    assert_response :success
    assert_select "h1", /Alertas/
  end

  test "PATCH /alerts/:id of another user is not found" do
    other_user = User.create!(name: "Other", email: "alerts_other_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_category = Category.create!(name: "Ajena_#{SecureRandom.hex(4)}", category_type: "expense", user: other_user)
    other_alert = SpendingAlert.create!(user: other_user, category: other_category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 100)

    patch alert_path(other_alert), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    assert_response :not_found
    assert_not other_alert.reload.read?
  end

  test "PATCH /alerts/mark_all_read marks every unread alert as read" do
    patch mark_all_read_alerts_path

    assert_redirected_to alerts_path
    assert_equal 0, @user.spending_alerts.unread.count
    assert_equal 3, @user.spending_alerts.where.not(read_at: nil).count
  end

  test "a user with no alerts sees an empty center without errors" do
    SpendingAlert.where(user: @user).destroy_all
    get alerts_path
    assert_response :success
    patch mark_all_read_alerts_path
    assert_redirected_to alerts_path
  end
end

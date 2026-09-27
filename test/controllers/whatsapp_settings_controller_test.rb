# frozen_string_literal: true

require "test_helper"

# Settings → WhatsApp section: status display, the primary CONNECT token
# button with deep link, the polling status endpoint, and disconnect/cancel.
# Authentication required; the phone number is never typed by the user —
# ownership is proven by the CONNECT command sent from WhatsApp.
class WhatsappSettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Whatsapp Settings User",
      email: "whatsapp_settings_controller_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "GET /settings/whatsapp requires authentication" do
    sign_out @user
    get whatsapp_settings_path
    assert_redirected_to new_user_session_path
  end

  test "GET /status requires authentication" do
    sign_out @user
    get status_whatsapp_settings_path
    assert_redirected_to new_user_session_path
  end

  test "GET /settings/whatsapp shows Not connected with a ready-to-use token button" do
    get whatsapp_settings_path

    assert_response :success
    assert_match "No conectado", response.body
    assert_match(/CONNECT\s+[A-Z2-9]{5}/, response.body)
    assert @user.pending_whatsapp_connections.unused.unexpired.last.present?
  end

  test "a page refresh generates a fresh token without consuming previous ones" do
    get whatsapp_settings_path
    first_pending = @user.pending_whatsapp_connections.unused.unexpired.last

    get whatsapp_settings_path

    second_pending = @user.pending_whatsapp_connections.unused.unexpired.order(:id).last
    assert_not_equal first_pending.id, second_pending.id
    assert_nil first_pending.reload.used_at, "old token must remain valid until it expires"
  end

  test "a refresh never lands on the Connecting state" do
    PendingWhatsappConnection.generate_for!(@user)

    get whatsapp_settings_path

    assert_response :success
    assert_match "No conectado", response.body
    assert_match 'data-connect-state="connecting" hidden', response.body
    assert_match 'data-connect-state="idle" >', response.body
  end

  test "GET /settings/whatsapp shows the connected phone when connected" do
    identity = WhatsappIdentity.create!(
      phone_number: "573001234567",
      claimed_by_user: @user,
      claimed_at: 1.day.ago
    )
    WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: 1.day.ago)

    get whatsapp_settings_path

    assert_response :success
    assert_match "Conectado", response.body
    assert_match "+57 300 123 4567", response.body
    assert_no_difference -> { PendingWhatsappConnection.count } do
      get whatsapp_settings_path
    end
  end

  test "GET /status reports disconnected when nothing is pending" do
    get status_whatsapp_settings_path, as: :json

    assert_response :success
    assert_equal({ "status" => "disconnected" }, JSON.parse(response.body))
  end

  test "GET /status reports pending while a token is unused and unexpired" do
    PendingWhatsappConnection.generate_for!(@user)

    get status_whatsapp_settings_path, as: :json

    assert_response :success
    assert_equal({ "status" => "pending" }, JSON.parse(response.body))
  end

  test "GET /status reports disconnected when the pending token expired" do
    travel_to 15.minutes.ago do
      PendingWhatsappConnection.generate_for!(@user)
    end

    get status_whatsapp_settings_path, as: :json

    assert_response :success
    assert_equal({ "status" => "disconnected" }, JSON.parse(response.body))
  end

  test "GET /status reports connected with the phone number when connected" do
    identity = WhatsappIdentity.create!(
      phone_number: "573001234567",
      claimed_by_user: @user,
      claimed_at: 1.day.ago
    )
    WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: 1.day.ago)

    get status_whatsapp_settings_path, as: :json

    assert_response :success
    assert_equal({ "status" => "connected", "phone_number" => "+573001234567" }, JSON.parse(response.body))
  end

  test "DELETE /settings/whatsapp/pending cancels the pending attempt" do
    PendingWhatsappConnection.generate_for!(@user)
    pending_row = @user.pending_whatsapp_connections.last

    delete cancel_whatsapp_settings_path

    assert_response :success
    assert_not_nil pending_row.reload.used_at
  end

  test "DELETE /settings/whatsapp disconnects and keeps expenses and identity" do
    identity = WhatsappIdentity.create!(
      phone_number: "573001234567",
      claimed_by_user: @user,
      claimed_at: 1.day.ago
    )
    connection = WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: 1.day.ago)
    category = Category.find_by(name: "Restaurants") ||
               Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    expense = @user.expenses.create!(
      description: "Almuerzo",
      amount: 50_000,
      date: Date.current,
      category: category
    )

    delete whatsapp_settings_path

    assert_redirected_to whatsapp_settings_path
    assert_not_nil connection.reload.disconnected_at
    assert WhatsappIdentity.exists?(identity.id)
    assert Expense.exists?(expense.id)
  end

  test "DELETE /settings/whatsapp without a connection does not raise" do
    delete whatsapp_settings_path

    assert_redirected_to whatsapp_settings_path
  end
end

# frozen_string_literal: true

require "test_helper"

# Settings → WhatsApp section: the two association states, the primary
# "Enviar mensaje" deep link (greeting + single-use CONNECT token), the polling
# status endpoint, and disconnect/cancel. Authentication required; the phone
# number is never typed by the user — ownership is proven by the token sent
# from WhatsApp itself.
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

  test "GET /settings/whatsapp shows the disconnected state and a secure WhatsApp deep link" do
    with_env("WHATSAPP_BUSINESS_NUMBER" => "573001112233") do
      get whatsapp_settings_path
    end

    assert_response :success
    assert_select "h1", text: /Gastos por WhatsApp/
    assert_match "Gastos por WhatsApp inactivos", response.body
    assert_match "Registra tus gastos por WhatsApp", response.body
    assert_match "Tu privacidad está protegida", response.body

    link = css_select("a[data-connect-action]").first
    assert_not_nil link, "the primary action must open WhatsApp"
    uri = URI.parse(link["href"])
    assert_equal "wa.me", uri.host
    assert_equal "/573001112233", uri.path

    message = Rack::Utils.parse_query(uri.query).fetch("text")
    assert message.start_with?("Hola yogasto quiero registrar mis gastos usando whatsapp"), message
    code = message[/CONNECT ([A-Z2-9]{5})\z/, 1]
    assert_not_nil code, "the initial message must carry a single-use connect token"
    assert PendingWhatsappConnection.valid_pending_for(code).present?
    assert @user.pending_whatsapp_connections.unused.unexpired.last.present?
  end

  test "a page refresh generates a fresh token without consuming previous ones" do
    get whatsapp_settings_path
    first_pending = @user.pending_whatsapp_connections.unused.unexpired.order(:created_at, :id).last

    get whatsapp_settings_path

    second_pending = @user.pending_whatsapp_connections.unused.unexpired.order(:created_at, :id).last
    assert_not_equal first_pending.id, second_pending.id
    assert_nil first_pending.reload.used_at, "old token must remain valid until it expires"
  end

  test "a refresh never lands on the Connecting state" do
    PendingWhatsappConnection.generate_for!(@user)

    get whatsapp_settings_path

    assert_response :success
    assert_match "Gastos por WhatsApp inactivos", response.body
    assert_select "[data-connect-state='connecting'][hidden]", count: 1
    assert_select "[data-connect-state='idle']:not([hidden])", count: 1
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
    assert_match "Gastos por WhatsApp activos", response.body
    assert_match "Recibiendo tus gastos por WhatsApp", response.body
    assert_match "+57 300 123 4567", response.body
    assert_match "Desconectar WhatsApp", response.body
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

  test "GET /status reports connected without exposing the phone number" do
    identity = WhatsappIdentity.create!(
      phone_number: "573001234567",
      claimed_by_user: @user,
      claimed_at: 1.day.ago
    )
    WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: 1.day.ago)

    get status_whatsapp_settings_path, as: :json

    assert_response :success
    assert_equal({ "status" => "connected" }, JSON.parse(response.body))
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
      category: category,
      money_source: @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
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

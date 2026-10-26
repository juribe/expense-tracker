require "test_helper"

class EmailSourcesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "ESC", email: "esc_#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  test "requires authentication" do
    sign_out :user
    get email_sources_path
    assert_redirected_to new_user_session_path
  end

  test "index renders onboarding heading" do
    get email_sources_path
    assert_response :success
    assert_select "h1", text: "Conecta tus correos"
  end

  test "shows forwarding address" do
    get email_sources_path
    assert_select "[data-testid='forwarding-address']"
  end

  test "initial setup shows only the add action" do
    get email_sources_path

    assert_select "#initialActions button", count: 1, text: "Agregar redirección"
    assert_select "#nextActions[hidden]" do
      assert_select "button", text: "Ya configuré el reenvío · Buscar correo"
    end
    assert_select "#setupInstructions[hidden]"
  end

  test "pending source shows an accept action" do
    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "bank@example.com",
      status: "pending_setup"
    )

    get email_sources_path

    assert_select "form[action='#{confirm_email_source_path(source)}'] button", text: "Aceptar"
  end

  test "setup status reports a pending forwarding source" do
    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "bank@example.com",
      status: "pending_setup"
    )

    get email_sources_setup_status_path, headers: { "Accept" => "application/json" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "forwarding_email_detected", payload["state"]
    assert_equal source.id, payload.dig("source", "id")
    assert_equal "bank@example.com", payload.dig("source", "email")
    assert payload["checked_at"].present?
    refute payload.key?("verification")
  end

  test "setup status exposes a safe confirmation url" do
    verification = @user.email_forwarding_verifications.create!(
      confirmation_url: "https://mail-settings.google.com/mail/vf-abc123",
      sender_email: "forwarding-noreply@google.com",
      subject: "Confirmación de reenvío de Gmail: recibir correo de bank@example.com",
      expires_at: 1.day.from_now
    )

    get email_sources_setup_status_path, headers: { "Accept" => "application/json" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal verification.id, payload.dig("verification", "id")
    assert_equal "https://mail-settings.google.com/mail/vf-abc123", payload.dig("verification", "url")
  end

  test "setup status hides an unsafe confirmation url" do
    @user.email_forwarding_verifications.create!(
      confirmation_url: "javascript:alert(1)",
      sender_email: "forwarding-noreply@google.com",
      subject: "Confirmación de reenvío de Gmail",
      expires_at: 1.day.from_now
    )

    get email_sources_setup_status_path, headers: { "Accept" => "application/json" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_nil payload.dig("verification", "url")
  end

  test "confirming the same verification twice does not duplicate sources" do
    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "bank@example.com",
      status: "pending_verification"
    )
    verification = @user.email_forwarding_verifications.create!(
      email_source: source,
      confirmation_url: "https://mail-settings.google.com/mail/vf-abc123",
      sender_email: "forwarding-noreply@google.com",
      subject: "Confirmación de reenvío de Gmail: recibir correo de bank@example.com",
      expires_at: 1.day.from_now
    )

    2.times do
      post confirm_email_verification_path(verification), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert_equal 1, @user.email_sources.count
    assert_equal "active", source.reload.status
    assert verification.reload.consumed?
  end

  test "confirming a pending source responds with JSON" do
    source = @user.email_sources.create!(
      source_type: "forwarding",
      email: "bank@example.com",
      status: "pending_setup"
    )

    post confirm_email_source_path(source), headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal "active", source.reload.status
    payload = JSON.parse(response.body)
    assert payload["ok"]
    assert_equal "active", payload.dig("source", "status")
  end

  test "confirming a gmail verification does not activate an unrelated pending source" do
    unrelated = @user.email_sources.create!(
      source_type: "forwarding",
      email: "jse.uribe@outlook.com",
      status: "pending_setup"
    )
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Confirmación de reenvío de Gmail: recibir correo de josuribee@gmail.com",
      "body_text" => "confirmation code 12345678",
      "html" => ""
    }
    verification = MailInbound::ForwardingVerificationDetector.store!(user: @user, message: message)

    assert_nil verification.email_source

    post confirm_email_verification_path(verification), headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal "pending_setup", unrelated.reload.status
    gmail_source = @user.email_sources.find_by(email: "josuribee@gmail.com")
    assert gmail_source
    assert_equal "active", gmail_source.status
    refute_equal unrelated, gmail_source
  end
end

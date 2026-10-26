require "test_helper"

class ForwardingVerificationDetectorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "FV", email: "fv_#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "detects gmail forwarding verification" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail Forwarding Confirmation",
      "body_text" => "To verify, enter confirmation code 12345678 or visit https://mail.google.com/mail/u/0/?verify=1",
      "html" => ""
    }
    assert MailInbound::ForwardingVerificationDetector.verification_message?(message)
    assert_equal "12345678", MailInbound::ForwardingVerificationDetector.extract_code(message)
    assert MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message).include?("mail.google.com")
  end

  test "stores verification without creating expense" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail Forwarding Confirmation",
      "body_text" => "confirmation code 87654321",
      "html" => ""
    }
    verification = MailInbound::ForwardingVerificationDetector.store!(user: @user, message: message)
    assert verification.persisted?
    assert_equal "87654321", verification.code
    assert verification.expires_at.future?
  end

  test "not a verification for normal bank email" do
    message = {
      "from" => "notificaciones@banco.com",
      "subject" => "Compra aprobada",
      "body_text" => "Monto 1000",
      "html" => ""
    }
    refute MailInbound::ForwardingVerificationDetector.verification_message?(message)
  end

  test "extracts the accept anchor instead of the cancel link" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Confirmación de reenvío de Gmail",
      "body_text" => "",
      "html" => <<~HTML
        <a href="https://mail-settings.google.com/mail/vf-cancel">Cancelar reenvío</a>
        <a href="https://mail-settings.google.com/mail/vf-confirm">Aceptar reenvío</a>
      HTML
    }

    assert_equal "https://mail-settings.google.com/mail/vf-confirm",
                 MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message)
  end

  test "ignores unrelated links in the same email" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail forwarding confirmation",
      "body_text" => "",
      "html" => <<~HTML
        <a href="https://policies.google.com/privacy">Privacy policy</a>
        <a href="https://mail-settings.google.com/mail/vf-confirm">Click here to accept forwarding</a>
      HTML
    }

    assert_equal "https://mail-settings.google.com/mail/vf-confirm",
                 MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message)
  end

  test "recognizes confirmation wording regardless of case and whitespace" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail forwarding confirmation",
      "body_text" => "",
      "html" => <<~HTML
        <a href="https://mail-settings.google.com/mail/vf-confirm">
          CLICK HERE TO ACCEPT FORWARDING
        </a>
      HTML
    }

    assert_equal "https://mail-settings.google.com/mail/vf-confirm",
                 MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message)
  end

  test "falls back to a plain text confirmation link" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail forwarding confirmation",
      "body_text" => "Confirm forwarding: https://mail.google.com/mail/confirm?token=secret",
      "html" => ""
    }

    assert_equal "https://mail.google.com/mail/confirm?token=secret",
                 MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message)
  end

  test "does not expose an unsafe confirmation link" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail forwarding confirmation",
      "body_text" => "Accept forwarding: javascript:alert(1)",
      "html" => '<a href="javascript:alert(1)">Accept forwarding</a>'
    }

    assert_nil MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message)
  end

  test "handles malformed html without raising" do
    message = {
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail forwarding confirmation",
      "body_text" => "",
      "html" => '<a href="https://mail-settings.google.com/mail/vf-confirm">Confirm forwarding'
    }

    assert_equal "https://mail-settings.google.com/mail/vf-confirm",
                 MailInbound::ForwardingVerificationDetector.extract_confirmation_url(message)
  end
end

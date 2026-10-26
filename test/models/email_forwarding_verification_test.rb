require "test_helper"

class EmailForwardingVerificationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "EV", email: "ev_#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "expired scope excludes active" do
    active = @user.email_forwarding_verifications.create!(code: "abc", expires_at: 1.day.from_now)
    expired = @user.email_forwarding_verifications.create!(code: "def", expires_at: 1.day.ago)
    assert_includes EmailForwardingVerification.active, active
    refute_includes EmailForwardingVerification.active, expired
    assert expired.expired?
  end

  test "safe confirmation url accepts allowed gmail links" do
    verification = @user.email_forwarding_verifications.create!(
      confirmation_url: "https://mail-settings.google.com/mail/vf-abc123",
      expires_at: 1.day.from_now
    )

    assert_equal "https://mail-settings.google.com/mail/vf-abc123", verification.safe_confirmation_url
  end

  test "safe confirmation url rejects unsafe links" do
    verification = @user.email_forwarding_verifications.create!(
      confirmation_url: "javascript:alert(1)",
      expires_at: 1.day.from_now
    )

    assert_nil verification.safe_confirmation_url
  end
end

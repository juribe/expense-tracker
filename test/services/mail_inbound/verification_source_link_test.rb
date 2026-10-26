require "test_helper"

class VerificationSourceLinkTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "VSL", email: "vsl_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @source = @user.email_sources.create!(source_type: "forwarding", status: "pending_verification")
  end

  test "verification links to pending forwarding source" do
    message = { "from" => "forwarding-noreply@google.com", "subject" => "Gmail Forwarding Confirmation", "body_text" => "code 998877", "html" => "" }
    v = MailInbound::ForwardingVerificationDetector.store!(user: @user, message: message)
    assert_equal @source, v.email_source
  end
end
require "test_helper"

class RecipientResolverDbTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "RR", email: "rr_#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "resolves user by inbound token" do
    base = "recibido@expense-tracker.com"
    recipient = "recibido+#{@user.inbound_email_token}@expense-tracker.com"
    resolver = MailInbound::RecipientResolver.new(recipient: recipient, base_recipient: base)
    assert_equal @user, resolver.user
  end
end
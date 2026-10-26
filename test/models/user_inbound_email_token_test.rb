require "test_helper"

class UserInboundEmailTokenTest < ActiveSupport::TestCase
  test "generates a stable unique token on create" do
    user = User.create!(name: "A", email: "a_#{SecureRandom.hex(4)}@example.com", password: "password123")
    assert user.inbound_email_token.present?
    token = user.inbound_email_token
    user.reload
    assert_equal token, user.inbound_email_token
  end

  test "forwarding address includes alias" do
    user = User.create!(name: "B", email: "b_#{SecureRandom.hex(4)}@example.com", password: "password123")
    with_env("INBOUND_EMAIL_RECIPIENT" => "recibido@expense-tracker.com") do
      assert_match(/\Arecibido\+.+@expense-tracker\.com\z/, user.forwarding_address)
    end
  end

  test "tokens are unique across users" do
    u1 = User.create!(name: "C", email: "c_#{SecureRandom.hex(4)}@example.com", password: "password123")
    u2 = User.create!(name: "D", email: "d_#{SecureRandom.hex(4)}@example.com", password: "password123")
    refute_equal u1.inbound_email_token, u2.inbound_email_token
  end
end
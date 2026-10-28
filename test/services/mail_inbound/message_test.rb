# frozen_string_literal: true

require "test_helper"

class MailInboundMessageTest < ActiveSupport::TestCase
  test "payload excludes the user record" do
    user = User.create!(
      name: "Message User",
      email: "mail_inbound_message_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    message = MailInbound::Message.new(
      provider: "cloudflare",
      external_id: "external-1",
      from: "Banco <notificaciones@bank.example>",
      to: [ "receive+user1@samyreplies.com" ],
      subject: "Compra aprobada",
      body_text: "Compra por $48.500",
      html: "<p>Compra por $48.500</p>",
      headers: [],
      attachments: [],
      internal_date: Time.current,
      recipient: "receive+user1@samyreplies.com",
      user: user
    )

    payload = message.to_payload

    assert_not payload.key?("user")
    assert_equal "external-1", payload["id"]
    assert_equal "Compra aprobada", payload["subject"]
    assert_equal "Compra por $48.500", payload["body_text"]
  end
end

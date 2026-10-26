# frozen_string_literal: true

require "test_helper"

class MailInbound::Providers::ResendTest < ActiveSupport::TestCase
  SECRET = "whsec_#{Base64.strict_encode64("resend-provider-secret")}"
  API_KEY = "re_test_key"

  setup do
    @user = User.create!(name: "Resend Provider", email: "resend_provider@example.com", password: "password123")
    @payload = {
      type: "email.received",
      created_at: "2026-10-25T15:00:00Z",
      data: {
        email_id: "em_resend_123",
        from: "sender@example.com",
        to: [ "receive+user1@samyreplies.com" ],
        subject: "Compra aprobada"
      }
    }.to_json
    @message_id = "msg_resend_123"
    @timestamp = Time.current.to_i.to_s
  end

  def request_for(body: @payload, recipient: "receive+user1@samyreplies.com", timestamp: @timestamp, secret: SECRET)
    signature = Svix::Webhook.new(secret).sign(@message_id, timestamp, body)
    MailInbound::Request.new(
      raw_body: body,
      headers: {
        "svix-id" => @message_id,
        "svix-timestamp" => timestamp,
        "svix-signature" => signature
      },
      params: {},
      content_type: "application/json"
    )
  end

  def with_env(&block)
    values = {
      "RESEND_WEBHOOK_SECRET" => SECRET,
      "RESEND_API_KEY" => API_KEY,
      "INBOUND_EMAIL_RECIPIENT" => "receive@samyreplies.com",
      "INBOUND_EMAIL_USER_EMAIL" => @user.email,
      "INBOUND_EMAIL_USER_MAP" => "user1=#{@user.email}"
    }
    original = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value.to_s }
    block.call
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "validates the Svix signature" do
    with_env do
      provider = MailInbound::Providers::Resend.new

      assert provider.valid_signature?(request_for)
      refute provider.valid_signature?(request_for(secret: "whsec_#{Base64.strict_encode64("wrong")}"))
    end
  end

  test "builds a delivery for email.received" do
    with_env do
      draft = MailInbound::Providers::Resend.new.build_delivery(request_for)

      assert_equal "resend", draft.provider
      assert_equal "em_resend_123", draft.external_id
      assert_equal @user, draft.user
      assert_equal "email.received", draft.params["type"]
    end
  end

  test "fetches and normalizes the received email" do
    response = ::Resend::Response.new(
      {
        id: "em_resend_123",
        from: "sender@example.com",
        to: [ "receive+user1@samyreplies.com" ],
        subject: "Compra aprobada",
        text: "Compra por $48.500",
        html: "<p>Compra por $48.500</p>",
        headers: { "from" => "sender@example.com" },
        attachments: [ { id: "att_1", filename: "receipt.pdf", content_type: "application/pdf" } ],
        created_at: "2026-10-25T15:00:00Z"
      },
      {}
    )

    with_env do
      provider = MailInbound::Providers::Resend.new
      draft = provider.build_delivery(request_for)
      delivery = MailInboundDelivery.create!(
        user: draft.user,
        provider: draft.provider,
        external_id: draft.external_id,
        raw_body: draft.raw_body,
        headers: draft.headers,
        params: draft.params
      )

      stub_method(::Resend::Emails::Receiving, :get, ->(_email_id) { response }) do
        message = provider.handle_email(delivery)

        assert_equal "resend", message.provider
        assert_equal "Compra por $48.500", message.body_text
        assert_equal "<p>Compra por $48.500</p>", message.html
        assert_equal "receipt.pdf", message.attachments.first["filename"]
        assert_equal "sender@example.com", message.headers.find { |h| h["name"] == "from" }["value"]
      end
    end
  end

  test "rejects a non-email.received event" do
    with_env do
      payload = JSON.parse(@payload).merge("type" => "email.delivered").to_json

      assert_raises(MailInbound::InvalidPayload) do
        MailInbound::Providers::Resend.new.build_delivery(request_for(body: payload))
      end
    end
  end
end

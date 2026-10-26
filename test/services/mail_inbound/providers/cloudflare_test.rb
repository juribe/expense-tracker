# frozen_string_literal: true

require "test_helper"

class MailInbound::Providers::CloudflareTest < ActiveSupport::TestCase
  SECRET = "cloudflare-provider-secret"

  setup do
    @user = User.create!(name: "Cloudflare Provider", email: "cloudflare_provider@example.com", password: "password123")
    @raw = raw_email
  end

  def raw_email
    mail = Mail.new
    mail.from = "Banco <notificaciones@bank.example>"
    mail.to = "receive+user1@samyreplies.com"
    mail.subject = "Compra aprobada"
    mail.message_id = "cloudflare-provider@example.com"
    mail.body = "Compra por $48.500"
    mail.to_s
  end

  def request_for(body: @raw, recipient: "receive+user1@samyreplies.com", timestamp: Time.current.to_i.to_s, secret: SECRET)
    signature = MailInbound::Providers::Cloudflare::SignatureVerifier.expected_signature(
      secret: secret, timestamp: timestamp, recipient: recipient, body: body
    )
    MailInbound::Request.new(
      raw_body: body,
      headers: {
        "X-Cloudflare-Email-Timestamp" => timestamp,
        "X-Cloudflare-Email-Recipient" => recipient,
        "X-Cloudflare-Email-Signature" => signature,
        "X-Cloudflare-Email-From" => "notificaciones@bank.example"
      },
      params: {},
      content_type: "message/rfc822"
    )
  end

  def with_env(&block)
    with_env_values(
      "INBOUND_EMAIL_SECRET" => SECRET,
      "INBOUND_EMAIL_RECIPIENT" => "receive@samyreplies.com",
      "INBOUND_EMAIL_USER_EMAIL" => @user.email,
      "INBOUND_EMAIL_USER_MAP" => "user1=#{@user.email}",
      "INBOUND_EMAIL_MAX_BYTES" => 10.megabytes.to_s
    ) { block.call }
  end

  def with_env_values(values, &block)
    original = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value.to_s }
    block.call
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "validates the Worker signature" do
    with_env do
      provider = MailInbound::Providers::Cloudflare.new

      assert provider.valid_signature?(request_for)
      refute provider.valid_signature?(request_for(secret: "wrong"))
    end
  end

  test "builds a durable delivery and resolves the user" do
    with_env do
      draft = MailInbound::Providers::Cloudflare.new.build_delivery(request_for)

      assert_equal "cloudflare", draft.provider
      assert_equal @user, draft.user
      assert_equal Digest::SHA256.hexdigest(@raw), draft.external_id
      assert_equal "receive+user1@samyreplies.com", draft.headers["recipient"]
    end
  end

  test "normalizes the MIME into a MailInbound message" do
    with_env do
      provider = MailInbound::Providers::Cloudflare.new
      draft = provider.build_delivery(request_for)
      delivery = MailInboundDelivery.create!(
        user: draft.user,
        provider: draft.provider,
        external_id: draft.external_id,
        raw_body: draft.raw_body,
        headers: draft.headers,
        params: draft.params
      )

      message = provider.handle_email(delivery)

      assert_equal "cloudflare", message.provider
      assert_equal draft.external_id, message.external_id
      assert_equal "Compra aprobada", message.subject
      assert_includes message.body_text, "Compra por $48.500"
      assert_equal @user, message.user
    end
  end

  test "rejects unsupported content types" do
    with_env do
      request = request_for
      request.content_type = "application/json"

      assert_raises(MailInbound::UnsupportedMediaType) do
        MailInbound::Providers::Cloudflare.new.build_delivery(request)
      end
    end
  end
end

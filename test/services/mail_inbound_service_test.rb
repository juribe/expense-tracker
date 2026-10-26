# frozen_string_literal: true

require "test_helper"

class MailInboundServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SECRET = "service-provider-secret"

  setup do
    @user = User.create!(name: "Inbound Service", email: "inbound_service@example.com", password: "password123")
    @raw = raw_email
  end

  def raw_email
    mail = Mail.new
    mail.from = "Banco <notificaciones@bank.example>"
    mail.to = "receive+user1@samyreplies.com"
    mail.subject = "Compra aprobada"
    mail.message_id = "inbound-service@example.com"
    mail.body = "Compra por $48.500"
    mail.to_s
  end

  def request_for(recipient: "receive+user1@samyreplies.com", secret: SECRET, raw: @raw)
    timestamp = Time.current.to_i.to_s
    signature = MailInbound::Providers::Cloudflare::SignatureVerifier.expected_signature(
      secret: secret, timestamp: timestamp, recipient: recipient, body: raw
    )
    MailInbound::Request.new(
      raw_body: raw,
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
    values = {
      "MAIL_INBOUND_PROVIDER" => "cloudflare",
      "INBOUND_EMAIL_SECRET" => SECRET,
      "INBOUND_EMAIL_RECIPIENT" => "receive@samyreplies.com",
      "INBOUND_EMAIL_USER_EMAIL" => @user.email,
      "INBOUND_EMAIL_USER_MAP" => "user1=#{@user.email}",
      "INBOUND_EMAIL_MAX_BYTES" => 10.megabytes.to_s
    }
    original = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value.to_s }
    block.call
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "accepts a signed delivery and enqueues the handle job" do
    with_env do
      with_active_job_adapter(:test) do
        assert_difference(-> { MailInboundDelivery.count }, 1) do
          assert_enqueued_with(job: MailInboundHandleJob) do
            result = MailInboundService.new.accept(request_for)

            assert_equal :accepted, result.status
            assert_equal "received", result.delivery.status
            assert_equal @user, result.delivery.user
          end
        end
      end
    end
  end

  test "rejects an invalid signature without persisting" do
    with_env do
      assert_no_difference(-> { MailInboundDelivery.count }) do
        result = MailInboundService.new.accept(request_for(secret: "wrong"))

        assert_equal :invalid_signature, result.status
      end
    end
  end

  test "duplicate deliveries do not enqueue another job" do
    with_env do
      with_active_job_adapter(:test) do
        assert_enqueued_jobs 1 do
          first = MailInboundService.new.accept(request_for)
          second = MailInboundService.new.accept(request_for)

          assert_equal :accepted, first.status
          assert_equal :duplicate, second.status
        end
      end
    end

    assert_equal 1, MailInboundDelivery.where(provider: "cloudflare").count
  end

  test "unknown recipient token is rejected" do
    with_env do
      result = MailInboundService.new.accept(request_for(recipient: "receive+unknown@samyreplies.com"))

      assert_equal :unknown_recipient, result.status
    end
  end

  test "queue failures are observable and mark the delivery failed" do
    with_env do
      stub_method(MailInboundHandleJob, :perform_later, ->(*) { raise ActiveRecord::StatementInvalid, "queue down" }) do
        result = MailInboundService.new.accept(request_for)

        assert_equal :queue_unavailable, result.status
        assert_equal "failed", result.delivery.status
      end
    end
  end
end

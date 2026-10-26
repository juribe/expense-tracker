# frozen_string_literal: true

require "test_helper"

class EmailWebhookControllerTest < ActionDispatch::IntegrationTest
  SECRET = "controller-inbound-secret"
  RECIPIENT = "receive+user1@samyreplies.com"

  setup do
    @user = User.create!(
      name: "Inbound Controller",
      email: "inbound_controller@example.com",
      password: "password123"
    )
    @raw = raw_email
  end

  def raw_email
    mail = Mail.new
    mail.from = "Banco <notificaciones@bank.example>"
    mail.to = RECIPIENT
    mail.subject = "Compra aprobada"
    mail.message_id = "controller-inbound@example.com"
    mail.body = "Compra por $48.500"
    mail.to_s
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

  def signed_headers(body, recipient: RECIPIENT, timestamp: Time.current.to_i.to_s, secret: SECRET)
    signature = MailInbound::Providers::Cloudflare::SignatureVerifier.expected_signature(
      secret: secret, timestamp: timestamp, recipient: recipient, body: body
    )

    {
      "Content-Type" => "message/rfc822",
      "X-Cloudflare-Email-Timestamp" => timestamp,
      "X-Cloudflare-Email-Recipient" => recipient,
      "X-Cloudflare-Email-Signature" => signature,
      "X-Cloudflare-Email-From" => "notificaciones@bank.example"
    }
  end

  def post_email(body: @raw, headers: nil)
    post webhooks_email_path, params: body, headers: headers || signed_headers(body)
  end

  test "accepts a signed delivery and enqueues only the handle job" do
    with_env do
      with_active_job_adapter(:test) do
        assert_difference(-> { MailInboundDelivery.count }, 1) do
          assert_no_difference(-> { ProcessedEmail.count }) do
            assert_enqueued_with(job: MailInboundHandleJob) { post_email }
          end
        end
      end
    end

    assert_response :accepted
    assert_equal "accepted", response.parsed_body["status"]
    delivery = MailInboundDelivery.find_by!(provider: "cloudflare")
    assert_equal "received", delivery.status
    assert_equal @user, delivery.user
  end

  test "rejects an invalid signature without persisting" do
    headers = signed_headers(@raw).merge("X-Cloudflare-Email-Signature" => "0" * 64)

    with_env do
      with_active_job_adapter(:test) do
        assert_no_difference(-> { MailInboundDelivery.count }) do
          assert_no_enqueued_jobs { post_email(headers: headers) }
        end
      end
    end

    assert_response :unauthorized
  end

  test "deduplicates the same delivery" do
    with_env do
      with_active_job_adapter(:test) do
        assert_enqueued_jobs 1 do
          post_email
          assert_response :accepted

          post_email
          assert_response :ok
          assert_equal "duplicate", response.parsed_body["status"]
        end
      end
    end

    assert_equal 1, MailInboundDelivery.count
  end

  test "rejects an unknown plus token" do
    headers = signed_headers(@raw, recipient: "receive+unknown@samyreplies.com")

    with_env do
      post_email(headers: headers)
    end

    assert_response :forbidden
  end

  test "rejects an unsupported content type" do
    body = "{}"
    headers = signed_headers(body).merge("Content-Type" => "application/json")

    with_env do
      post_email(body: body, headers: headers)
    end

    assert_response :unsupported_media_type
  end

  test "rejects an oversized payload" do
    with_env do
      original = ENV["INBOUND_EMAIL_MAX_BYTES"]
      ENV["INBOUND_EMAIL_MAX_BYTES"] = "10"
      begin
        post_email
      ensure
        ENV["INBOUND_EMAIL_MAX_BYTES"] = original
      end
    end

    assert_response 413
  end

  test "returns 503 when the handle job cannot be enqueued" do
    with_env do
      stub_method(MailInboundHandleJob, :perform_later, ->(*) { raise ActiveRecord::StatementInvalid, "queue down" }) do
        post_email
      end
    end

    assert_response :service_unavailable
    assert_equal "failed", MailInboundDelivery.find_by!(provider: "cloudflare").status
  end
end

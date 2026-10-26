# frozen_string_literal: true

require "test_helper"

class MailInboundHandleJobTest < ActiveJob::TestCase
  SECRET = "handle-job-secret"

  setup do
    @user = User.create!(name: "Handle Job", email: "mail_inbound_handle_job@example.com", password: "password123")
    @raw = raw_email
    @delivery = MailInboundDelivery.create!(
      user: @user,
      provider: "cloudflare",
      external_id: Digest::SHA256.hexdigest(@raw),
      raw_body: @raw,
      headers: {
        "content_type" => "message/rfc822",
        "from" => "notificaciones@bank.example",
        "recipient" => "receive+user1@samyreplies.com"
      }
    )
  end

  def raw_email
    mail = Mail.new
    mail.from = "Banco <notificaciones@bank.example>"
    mail.to = "receive+user1@samyreplies.com"
    mail.subject = "Compra aprobada"
    mail.message_id = "handle-job@example.com"
    mail.body = "Compra por $48.500"
    mail.to_s
  end

  def with_env(&block)
    values = {
      "INBOUND_EMAIL_SECRET" => SECRET,
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

  test "normalizes a delivery, creates ProcessedEmail and enqueues processing" do
    with_env do
      with_active_job_adapter(:test) do
        assert_difference(-> { ProcessedEmail.count }, 1) do
          assert_enqueued_with(job: MailInboundProcessJob) do
            MailInboundHandleJob.perform_now(@delivery.id)
          end
        end
      end
    end

    @delivery.reload
    assert_equal "handled", @delivery.status
    assert_equal "queued", @delivery.processed_email.status
    assert_equal "cloudflare", @delivery.processed_email.provider
    assert_equal @delivery.external_id, @delivery.processed_email.payload_data.dig("email", "id")
  end

  test "marks a permanent parse failure as failed without processing" do
    @delivery.update!(raw_body: "")

    with_env do
      assert_no_difference(-> { ProcessedEmail.count }) do
        MailInboundHandleJob.perform_now(@delivery.id)
      end
    end

    assert_equal "failed", @delivery.reload.status
    assert_match(/empty|parse/i, @delivery.last_error)
  end

  test "retries provider failures and leaves an observable failure" do
    fake_service = Object.new
    fake_service.define_singleton_method(:handle_email) do |_delivery|
      raise MailInbound::ProviderError, "upstream down"
    end

    with_env do
      with_active_job_adapter(:test) do
        stub_method(MailInboundService, :new, ->(*, **) { fake_service }) do
          assert_enqueued_with(job: MailInboundHandleJob, args: [ @delivery.id ]) do
            MailInboundHandleJob.perform_now(@delivery.id)
          end
        end
      end
    end

    assert_equal "failed", @delivery.reload.status
    assert_match(/upstream down/, @delivery.last_error)
  end
end

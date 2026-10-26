require "test_helper"

class MailInboundSourceRegistrationTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "SR", email: "sr_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @token = @user.inbound_email_token
  end

  test "unknown sender creates pending source and ignores email" do
    message = {
      "id" => "msg-2",
      "from" => "alertas@banco.com",
      "subject" => "Compra aprobada",
      "body_text" => "Monto 1000",
      "html" => "",
      "internal_date" => Time.current
    }
    email = ProcessedEmail.create!(
      user: @user,
      provider: "cloudflare",
      message_id: "msg-2",
      status: "queued",
      payload: JSON.generate("email" => message)
    )

    MailInboundProcessJob.perform_now(email.id)

    email.reload
    assert_equal "ignored", email.status
    assert @user.email_sources.exists?(email: "alertas@banco.com", status: "pending_setup")
  end

  test "accepted sender processes email" do
    @user.email_sources.create!(source_type: "forwarding", email: "alertas@banco.com", status: "active")
    message = {
      "id" => "msg-3",
      "from" => "alertas@banco.com",
      "subject" => "Compra aprobada",
      "body_text" => "Monto 1000",
      "html" => "",
      "internal_date" => Time.current
    }
    email = ProcessedEmail.create!(
      user: @user,
      provider: "cloudflare",
      message_id: "msg-3",
      status: "queued",
      payload: JSON.generate("email" => message)
    )

    MailInboundProcessJob.perform_now(email.id)

    email.reload
    # It may be ignored by transaction detector, but source registration should not block.
    refute_equal "email source not accepted", email.failure_reason
  end
end
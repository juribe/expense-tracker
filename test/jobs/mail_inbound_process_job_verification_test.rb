require "test_helper"

class MailInboundProcessJobVerificationTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "JV", email: "jv_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @token = @user.inbound_email_token
  end

  test "verification message is ignored and stored" do
    message = {
      "id" => "msg-1",
      "from" => "forwarding-noreply@google.com",
      "subject" => "Gmail Forwarding Confirmation",
      "body_text" => "confirmation code 11223344",
      "html" => "",
      "internal_date" => Time.current
    }
    email = ProcessedEmail.create!(
      user: @user,
      provider: "cloudflare",
      message_id: "msg-1",
      status: "queued",
      payload: JSON.generate("email" => message)
    )

    MailInboundProcessJob.perform_now(email.id)

    email.reload
    assert_equal "ignored", email.status
    assert @user.email_forwarding_verifications.exists?
    assert_nil email.payload_data["email"]
  end
end

require "test_helper"

class ConfirmationUrlValidatorTest < ActiveSupport::TestCase
  test "accepts an https gmail confirmation link" do
    url = "https://mail-settings.google.com/mail/vf-abc123?token=secret"

    assert_equal url, MailInbound::ConfirmationUrlValidator.call(url)
  end

  test "accepts a mail.google.com confirmation link" do
    url = "https://mail.google.com/mail/confirm?token=secret"

    assert_equal url, MailInbound::ConfirmationUrlValidator.call(url)
  end

  test "rejects http links" do
    assert_nil MailInbound::ConfirmationUrlValidator.call("http://mail-settings.google.com/mail/vf-abc123")
  end

  test "rejects non allowlisted hosts" do
    assert_nil MailInbound::ConfirmationUrlValidator.call("https://evil.example.com/mail/vf-abc123")
  end

  test "rejects executable and data urls" do
    assert_nil MailInbound::ConfirmationUrlValidator.call("javascript:alert(1)")
    assert_nil MailInbound::ConfirmationUrlValidator.call("data:text/html,hello")
  end

  test "rejects malformed urls" do
    assert_nil MailInbound::ConfirmationUrlValidator.call("not a url")
    assert_nil MailInbound::ConfirmationUrlValidator.call(nil)
  end

  test "decodes html escaped query separators" do
    url = "https://mail-settings.google.com/mail/vf-abc123?a=1&amp;b=2"

    assert_equal "https://mail-settings.google.com/mail/vf-abc123?a=1&b=2",
                 MailInbound::ConfirmationUrlValidator.call(url)
  end
end

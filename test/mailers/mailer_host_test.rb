# frozen_string_literal: true

require "test_helper"

class MailerHostTest < ActionMailer::TestCase
  test "devise reset mail uses the configured APP_HOST" do
    user = User.create!(
      name: "Mailer Host",
      email: "mailer_host@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    with_env("APP_HOST" => "app.example.test") do
      mail = Devise::Mailer.reset_password_instructions(user, "token-123")

      assert_includes mail.body.encoded, "http://app.example.test/users/password/edit"
    end
  end

  test "devise sender is not the generator placeholder" do
    refute_includes Devise.mailer_sender, "example.com"
  end
end

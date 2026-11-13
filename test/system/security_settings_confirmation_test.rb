# frozen_string_literal: true

require "application_system_test_case"

class SecuritySettingsConfirmationTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      name: "Security Confirmation User",
      email: "security-confirmation-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @user.create_totp_credential!(secret: TotpCredential.generate_secret)
  end

  test "adding a passkey opens confirmation before starting WebAuthn" do
    sign_in(@user)
    visit security_settings_path
    fill_in I18n.t("security.reauthentication.password_label"), with: "password123"
    click_button I18n.t("security.reauthentication.submit")

    within("[data-testid='passkey-creation-form']") do
      fill_in I18n.t("security.passkeys.name_label"), with: "MacBook personal"
      click_button I18n.t("security.passkeys.add")
    end

    assert_selector "[data-testid='security-confirmation-modal'].show"
    assert_no_selector "webauthn-create[data-ceremony-completed='true']"
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

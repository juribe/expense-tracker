# frozen_string_literal: true

require "test_helper"

class SecuritySettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user(email: "security-settings@example.com")
    sign_in @user
  end

  test "requires an authenticated user" do
    delete destroy_user_session_path

    get security_settings_path

    assert_redirected_to new_user_session_path
  end

  test "security pages are not cached" do
    get security_settings_path

    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "renders the account security page with every section" do
    reauthenticate

    get security_settings_path

    assert_response :success
    assert_select "h1", text: I18n.t("security.title", default: "Seguridad de la cuenta")
    assert_select "[data-testid='passkeys-card']"
    assert_select "[data-testid='two-factor-card']"
    assert_select "[data-testid='devices-card']"
    assert_select "[data-testid='recovery-codes-card']"
  end

  test "shows the real passkey count and two factor status" do
    create_credential(@user, factor: :first_factor, name: "MacBook personal")
    create_credential(@user, factor: :first_factor, name: "iPhone personal")
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")
    reauthenticate

    get security_settings_path

    assert_response :success
    assert_select "[data-testid='passkeys-count']", text: /2/
    assert_select "[data-testid='two-factor-status']",
                  text: I18n.t("security.two_factor.enabled", default: "Activado")
    assert_select "[data-testid='device-row']", count: 3
  end

  test "hides all security information until the user reauthenticates" do
    create_credential(@user, factor: :first_factor, name: "MacBook personal")
    create_totp_credential(@user)

    get security_settings_path

    assert_response :success
    assert_select "[data-testid='security-locked']"
    assert_select "[data-testid='reauthenticate-form']"
    assert_select "[data-testid='passkeys-card']", count: 0
    assert_select "[data-testid='two-factor-card']", count: 0
    assert_select "[data-testid='totp-card']", count: 0
    assert_select "[data-testid='devices-card']", count: 0
    assert_select "[data-testid='recovery-codes-card']", count: 0
    refute_includes response.body, "MacBook personal"
  end

  test "starts TOTP setup only after reauthentication" do
    post start_totp_setup_security_settings_path

    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select "[data-testid='security-locked']"
    assert_nil session[:totp_setup]
  end

  test "starting TOTP setup generates a pending secret without enabling TOTP" do
    reauthenticate

    post start_totp_setup_security_settings_path

    assert_redirected_to totp_setup_security_settings_path
    assert session[:totp_setup].present?
    assert session[:totp_setup]["secret"].present?
    refute @user.reload.totp_enabled?
  end

  test "the TOTP setup page requires reauthentication" do
    get totp_setup_security_settings_path

    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select "[data-testid='security-locked']"
    assert_select "[data-testid='totp-qr']", count: 0
  end

  test "shows the TOTP QR, manual secret and confirmation form" do
    secret = start_totp_setup

    get totp_setup_security_settings_path

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "[data-testid='totp-setup']"
    assert_select "[data-testid='totp-qr'] img[src^='data:image/svg+xml;base64,']"
    formatted_secret = secret.scan(/.{4}/).join(" ")
    assert_select "[data-testid='totp-secret']", text: /#{Regexp.escape(formatted_secret)}/
    assert_select "input[name='totp_code']"
    assert_select "[data-testid='totp-confirm-form']"
  end

  test "confirms TOTP with a valid code and shows recovery codes once" do
    secret = start_totp_setup
    code = ROTP::TOTP.new(secret).now

    post confirm_totp_security_settings_path, params: { totp_code: code }

    assert_response :success
    assert @user.reload.totp_enabled?
    assert_select "[data-testid='totp-card']"
    assert_select "[data-testid='recovery-codes-plaintext']"
    assert_equal 10, css_select("[data-recovery-code]").size
    assert_equal 10, RecoveryCode.where(user: @user).count
    assert_nil session[:totp_setup]
  end

  test "does not enable TOTP with an invalid code" do
    secret = start_totp_setup
    wrong_code = ROTP::TOTP.new(TotpCredential.generate_secret).now

    post confirm_totp_security_settings_path, params: { totp_code: wrong_code }

    assert_redirected_to totp_setup_security_settings_path
    refute @user.reload.totp_enabled?
    assert flash[:alert].present?
    assert session[:totp_setup].present?
  end

  test "expires the TOTP setup after ten minutes" do
    secret = start_totp_setup

    travel 11.minutes do
      get totp_setup_security_settings_path

      assert_redirected_to security_settings_path
      follow_redirect!
      assert_select ".alert-danger"

      post confirm_totp_security_settings_path, params: { totp_code: ROTP::TOTP.new(secret).now }
      assert_redirected_to security_settings_path
      refute @user.reload.totp_enabled?
    end
  end

  test "does not show the TOTP QR again after confirming" do
    secret = start_totp_setup
    post confirm_totp_security_settings_path, params: { totp_code: ROTP::TOTP.new(secret).now }

    get totp_setup_security_settings_path

    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select "[data-testid='totp-qr']", count: 0
  end

  test "cancels TOTP setup and clears the pending secret" do
    start_totp_setup

    delete cancel_totp_setup_security_settings_path

    assert_redirected_to security_settings_path
    assert_nil session[:totp_setup]
    refute @user.reload.totp_enabled?
  end

  test "changing TOTP replaces the secret only after confirmation" do
    travel_to(Time.zone.parse("2026-01-01 12:00:00")) do
      old_credential = create_totp_credential(@user)
      old_code = ROTP::TOTP.new(old_credential.secret).now
      reauthenticate

      post start_totp_setup_security_settings_path, params: { totp_code: old_code }
      new_secret = session[:totp_setup]["secret"]
      assert @user.reload.totp_enabled?

      post confirm_totp_security_settings_path, params: { totp_code: ROTP::TOTP.new(new_secret).now }

      assert_response :success
      new_credential = @user.reload.totp_credential
      assert_equal new_secret, new_credential.secret
      refute new_credential.verify_and_consume!(old_code)

      future = Time.current + 30.seconds
      assert new_credential.verify_and_consume!(ROTP::TOTP.new(new_secret).at(future), at: future)
    end
  end

  test "shows the TOTP card status and actions" do
    reauthenticate
    get security_settings_path
    assert_select "[data-testid='totp-card']"
    assert_select "[data-testid='totp-status']", text: I18n.t("security.totp.disabled", default: "Desactivada")
    assert_select "[data-testid='totp-setup-button']"

    create_totp_credential(@user)

    get security_settings_path
    assert_select "[data-testid='totp-status']", text: I18n.t("security.totp.enabled", default: "Activada")
    assert_select "[data-testid='totp-change-button']"
    assert_select "[data-testid='totp-disable-button']"
  end

  test "disabling TOTP requires reauthentication" do
    create_totp_credential(@user)

    delete disable_totp_security_settings_path

    assert_redirected_to security_settings_path
    assert @user.reload.totp_enabled?
    follow_redirect!
    assert_select "[data-testid='security-locked']"
  end

  test "disabling TOTP without a verification code is rejected" do
    create_totp_credential(@user)
    reauthenticate

    delete disable_totp_security_settings_path

    assert_redirected_to security_settings_path
    assert @user.reload.totp_enabled?
  end

  test "disabling TOTP with the current code removes it and its recovery codes when no MFA remains" do
    create_totp_credential(@user)
    RecoveryCode.generate_for(@user)
    reauthenticate

    delete disable_totp_security_settings_path, params: { totp_code: current_totp_code(@user) }

    assert_redirected_to security_settings_path
    refute @user.reload.totp_enabled?
    assert_equal 0, RecoveryCode.where(user: @user).count
  end

  test "disabling TOTP with a recovery code removes it" do
    create_totp_credential(@user)
    recovery_code = RecoveryCode.generate_for(@user).first
    reauthenticate

    delete disable_totp_security_settings_path, params: { recovery_code: recovery_code }

    assert_redirected_to security_settings_path
    refute @user.reload.totp_enabled?
    assert_equal 0, RecoveryCode.where(user: @user).count
  end

  test "disabling TOTP keeps recovery codes when a WebAuthn second factor remains" do
    create_totp_credential(@user)
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")
    RecoveryCode.generate_for(@user)
    reauthenticate

    delete disable_totp_security_settings_path, params: { totp_code: current_totp_code(@user) }

    assert_redirected_to security_settings_path
    refute @user.reload.totp_enabled?
    assert_equal 1, @user.second_factor_webauthn_credentials.count
    assert_equal 10, RecoveryCode.where(user: @user).count
  end

  test "disabling WebAuthn keeps recovery codes when TOTP remains" do
    create_totp_credential(@user)
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")
    RecoveryCode.generate_for(@user)
    reauthenticate

    delete disable_two_factor_security_settings_path, params: { totp_code: current_totp_code(@user) }

    assert_redirected_to security_settings_path
    assert_equal 0, @user.second_factor_webauthn_credentials.count
    assert @user.reload.totp_enabled?
    assert_equal 10, RecoveryCode.where(user: @user).count
  end

  test "does not modify another user's TOTP credential" do
    other_user = create_user(email: "other-totp-security@example.com")
    other_secret = create_totp_credential(other_user).secret
    create_totp_credential(@user)
    reauthenticate

    delete disable_totp_security_settings_path, params: { totp_code: current_totp_code(@user) }

    refute @user.reload.totp_enabled?
    assert other_user.reload.totp_enabled?
    assert_equal other_secret, other_user.totp_credential.secret
  end

  test "rotating TOTP requires the current code" do
    create_totp_credential(@user)
    reauthenticate

    post start_totp_setup_security_settings_path

    assert_redirected_to security_settings_path
    assert_nil session[:totp_setup]
  end

  test "rotating TOTP with the current code starts a new setup" do
    create_totp_credential(@user)
    reauthenticate

    post start_totp_setup_security_settings_path, params: { totp_code: current_totp_code(@user) }

    assert_redirected_to totp_setup_security_settings_path
    assert session[:totp_setup]["secret"].present?
    refute_equal @user.totp_credential.secret, session[:totp_setup]["secret"]
  end

  test "shows recovery codes for a TOTP-only account" do
    create_totp_credential(@user)
    RecoveryCode.generate_for(@user)
    reauthenticate

    get security_settings_path

    assert_response :success
    assert_select "[data-testid='recovery-codes-card']"
    assert_select "[data-testid='recovery-codes-card']", text: /10/
  end

  test "reauthentication with the current password unlocks sensitive actions" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_redirected_to security_settings_path
    follow_redirect!

    assert_response :success
    assert_select "[data-testid='security-locked']", count: 0
    assert_select "[data-testid='passkeys-card']"
    assert_select "[data-testid='two-factor-card']"
    assert_select "[data-testid='passkey-form']"
    assert_select "[data-testid='two-factor-form']"
    assert_select ".alert-success"
  end

  test "reauthentication with a wrong password does not unlock sensitive actions" do
    post reauthenticate_security_settings_path, params: { current_password: "wrong-password" }

    assert_redirected_to security_settings_path
    follow_redirect!

    assert_response :success
    assert_select "[data-testid='security-locked']"
    assert_select "[data-testid='passkey-form']", count: 0
    assert_select "[data-testid='reauthenticate-form']"
    assert_select ".alert-danger"
  end

  test "reauthentication expires after ten minutes" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    travel 11.minutes do
      get security_settings_path

      assert_select "[data-testid='security-locked']"
      assert_select "[data-testid='passkeys-card']", count: 0
      assert_select "[data-testid='passkey-form']", count: 0
      assert_select "[data-testid='reauthenticate-form']"
    end
  end

  test "regenerating recovery codes requires reauthentication" do
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")

    assert_no_difference -> { RecoveryCode.where(user: @user).count } do
      post regenerate_recovery_codes_security_settings_path
    end

    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select "[data-testid='security-locked']"
    assert_select ".alert-danger"
  end

  test "regenerating recovery codes requires two factor authentication to be enabled" do
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_no_difference -> { RecoveryCode.where(user: @user).count } do
      post regenerate_recovery_codes_security_settings_path
    end

    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select ".alert-danger"
  end

  test "regenerating recovery codes shows them once and stores only hashes" do
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    post regenerate_recovery_codes_security_settings_path

    assert_response :success
    assert_select "[data-testid='recovery-codes-plaintext']"
    codes = css_select("[data-recovery-code]").map { |node| node.text.strip }
    assert_equal 10, codes.uniq.size

    records = RecoveryCode.where(user: @user).to_a
    assert_equal 10, records.size
    records.each do |record|
      assert record.code_digest.present?
      codes.each { |code| refute_equal code, record.code_digest }
    end

    get security_settings_path
    assert_response :success
    refute_includes response.body, codes.first
  end

  test "disabling two factor without a verification code is rejected" do
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")
    RecoveryCode.generate_for(@user)
    reauthenticate

    assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
      delete disable_two_factor_security_settings_path
    end

    assert_redirected_to security_settings_path
  end

  test "disabling two factor with a recovery code removes credentials but keeps passkeys" do
    create_credential(@user, factor: :first_factor, name: "MacBook personal")
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")
    recovery_code = RecoveryCode.generate_for(@user).first
    post reauthenticate_security_settings_path, params: { current_password: "password123" }

    assert_difference -> { @user.second_factor_webauthn_credentials.count }, -1 do
      delete disable_two_factor_security_settings_path, params: { recovery_code: recovery_code }
    end

    assert_equal 0, RecoveryCode.where(user: @user).count
    assert_equal 1, @user.passkeys.count
    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select ".alert-success"
  end

  test "disabling two factor requires reauthentication" do
    create_credential(@user, factor: :second_factor, name: "Llave de seguridad")

    assert_no_difference -> { @user.second_factor_webauthn_credentials.count } do
      delete disable_two_factor_security_settings_path
    end

    assert_redirected_to security_settings_path
    follow_redirect!
    assert_select "[data-testid='security-locked']"
    assert_select ".alert-danger"
  end

  test "does not expose another user's credentials" do
    other_user = create_user(email: "other-security@example.com")
    create_credential(other_user, factor: :first_factor, name: "Dispositivo ajeno")
    reauthenticate

    get security_settings_path

    assert_response :success
    refute_includes response.body, "Dispositivo ajeno"
    assert_select "[data-testid='device-row']", count: 0
  end

  private

  def reauthenticate(password: "password123")
    post reauthenticate_security_settings_path, params: { current_password: password }
  end

  def start_totp_setup
    reauthenticate
    post start_totp_setup_security_settings_path
    assert_redirected_to totp_setup_security_settings_path
    session[:totp_setup]["secret"]
  end

  def create_totp_credential(user, secret: TotpCredential.generate_secret)
    user.create_totp_credential!(secret: secret)
  end

  def current_totp_code(user)
    ROTP::TOTP.new(user.totp_credential.secret).now
  end

  def create_user(email:)
    User.create!(
      name: "Security User",
      email: email,
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def create_credential(user, factor:, name:)
    user.webauthn_credentials.create!(
      external_id: SecureRandom.urlsafe_base64(16),
      name: name,
      public_key: SecureRandom.base64(32),
      sign_count: 0,
      authentication_factor: factor
    )
  end
end

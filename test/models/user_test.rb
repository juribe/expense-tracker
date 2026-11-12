# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "users no longer have the requires_membership column" do
    refute_includes User.column_names, "requires_membership"
  end

  test "users are not admins by default" do
    user = User.create!(
      name: "Regular User",
      email: "regular-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )

    refute user.admin?
  end

  # Form labels for User fields render through human_attribute_name; without
  # es translations they fall back to English ("Name", "Current password").
  test "user attribute labels are translated to Spanish" do
    assert_equal "Nombre completo", User.human_attribute_name(:name)
    assert_equal "Correo electrónico", User.human_attribute_name(:email)
    assert_equal "Contraseña", User.human_attribute_name(:password)
    assert_equal "Confirmar contraseña", User.human_attribute_name(:password_confirmation)
    assert_equal "Contraseña actual", User.human_attribute_name(:current_password)
    assert_equal "Día de inicio del ciclo financiero", User.human_attribute_name(:financial_cycle_start_day)
    assert_equal "Porcentaje objetivo de capacidad de deuda", User.human_attribute_name(:debt_capacity_target_percentage)
    assert_equal "Porcentaje de alerta de capacidad de deuda", User.human_attribute_name(:debt_capacity_alert_percentage)
  end

  test "registration requires terms and privacy acceptance" do
    user = build_registration_user(terms_accepted: "0", privacy_accepted: "0")

    refute user.valid?
    assert_includes user.errors.full_messages,
                    I18n.t("auth.consents.terms_required",
                           default: "Debes aceptar los Términos y condiciones para crear tu cuenta.")
    assert_includes user.errors.full_messages,
                    I18n.t("auth.consents.privacy_required",
                           default: "Debes aceptar la Política de privacidad para crear tu cuenta.")
  end

  test "registration does not require marketing consent" do
    user = build_registration_user(marketing_consent: "0")

    assert user.valid?
  end

  test "direct user creation does not require registration consents" do
    user = User.create!(
      name: "Direct User",
      email: "direct-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    assert user.persisted?
    assert_equal 0, user.user_consents.count
  end

  test "registration records consents after creating the user" do
    user = build_registration_user(marketing_consent: "1")

    assert_difference -> { UserConsent.count }, 3 do
      user.save!
    end

    assert_equal 2, user.user_consents.legal.count
    assert user.user_consents.marketing.first.granted?
  end

  test "registration records declined marketing consent" do
    user = build_registration_user(marketing_consent: "0")
    user.save!

    marketing = user.user_consents.marketing.first

    assert marketing.present?
    refute marketing.granted?
  end

  test "registration requires a name" do
    user = build_registration_user(name: "")

    refute user.valid?
    assert user.errors[:name].present?
  end

  test "registration rejects a whitespace-only name" do
    user = build_registration_user(name: "   ")

    refute user.valid?
    assert user.errors[:name].present?
  end

  test "rejects names longer than the maximum length" do
    user = build_registration_user(name: "a" * 256)

    refute user.valid?
    assert user.errors[:name].present?
  end

  test "prevents blanking an existing name" do
    user = User.create!(
      name: "Valid Name",
      email: "rename-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    refute user.update(name: "")
    assert user.errors[:name].present?
  end

  test "allows legacy blank names to update other attributes" do
    user = User.create!(
      name: "Legacy Name",
      email: "legacy-name-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    user.update_column(:name, "")

    assert user.update(financial_cycle_start_day: 2)
    assert_equal 2, user.reload.financial_cycle_start_day
  end

  test "cannot change the account email to one used by another premium account" do
    owner = User.create!(
      name: "Premium Email Owner",
      email: "premium-email-owner-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: "claimed-account@example.com",
      user: owner
    )
    user = User.create!(
      name: "Email Changer",
      email: "email-changer-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )

    assert_not user.update(email: "claimed-account@example.com")
    assert_includes user.errors[:email], "ya fue utilizada por una cuenta con membresía premium"
  end

  test "can change the account email to one already claimed by the same user" do
    user = User.create!(
      name: "Own Email Identity",
      email: "own-email-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: "own-new-email@example.com",
      user: user
    )

    assert user.update(email: "own-new-email@example.com")
    assert_equal "own-new-email@example.com", user.reload.unconfirmed_email
  end

  test "changing the email of a premium account records the new account identity" do
    membership_type = PaymentEngine::MembershipType.create!(
      name: "Email Change Premium",
      code: "EMAIL_CHANGE_#{SecureRandom.hex(6)}",
      status: "active"
    )
    user = User.create!(
      name: "Premium Email Change",
      email: "premium-email-change-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.day.ago,
      expires_at: 1.month.from_now
    )
    new_email = "premium-email-changed-#{SecureRandom.hex(4)}@example.com"

    user.update!(email: new_email)
    user.confirm

    identity = PremiumIdentity.find_by(
      identity_type: "account_email",
      fingerprint: PremiumIdentities::Fingerprint.call(identity_type: "account_email", value: new_email)
    )
    assert identity
    assert_equal user.id, identity.first_user_id
  end

  test "changing the email of a free account does not record a premium identity" do
    user = User.create!(
      name: "Free Email Change",
      email: "free-email-change-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    new_email = "free-email-changed-#{SecureRandom.hex(4)}@example.com"

    assert_no_difference -> { PremiumIdentity.count } do
      user.update!(email: new_email)
      user.confirm
    end
  end

  private

  def build_registration_user(overrides = {})
    User.new({
      name: "Registration Consent User",
      email: "registration-consent-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      registration_form: true,
      terms_accepted: "1",
      privacy_accepted: "1"
    }.merge(overrides))
  end
end

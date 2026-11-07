# frozen_string_literal: true

require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Old Name",
      email: "registrations_ctrl_test@example.com",
      password: "password123"
    )
    @user.confirm
    sign_in @user
  end

  test "PUT /users stays signed in with a changed name without passwords" do
    put user_registration_path, params: {
      user: {
        name: "Nuevo Nombre",
        email: @user.email,
        password: "",
        password_confirmation: "",
        current_password: ""
      }
    }

    assert_redirected_to root_path
    @user.reload
    assert_equal "Nuevo Nombre", @user.name
  end

  test "sign up without legal acceptances is rejected" do
    sign_out :user

    assert_no_difference("User.count") do
      assert_no_difference("UserConsent.count") do
        post user_registration_path, params: {
          user: sign_up_params(terms_accepted: "0", privacy_accepted: "0")
        }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("auth.consents.terms_required", default: "Debes aceptar los Términos y condiciones para crear tu cuenta.")
    assert_includes response.body, I18n.t("auth.consents.privacy_required", default: "Debes aceptar la Política de privacidad para crear tu cuenta.")
  end

  test "sign up without a name is rejected" do
    sign_out :user

    assert_no_difference("User.count") do
      post user_registration_path, params: {
        user: sign_up_params(name: "")
      }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
    assert_includes response.body, I18n.t("errors.messages.blank", default: "no puede estar en blanco")
  end

  test "sign up requires privacy acceptance independently from terms" do
    sign_out :user

    assert_no_difference("User.count") do
      post user_registration_path, params: {
        user: sign_up_params(terms_accepted: "1", privacy_accepted: "0")
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("auth.consents.privacy_required", default: "Debes aceptar la Política de privacidad para crear tu cuenta.")
    refute_includes response.body, I18n.t("auth.consents.terms_required", default: "Debes aceptar los Términos y condiciones para crear tu cuenta.")
  end

  test "sign up requires terms acceptance independently from privacy" do
    sign_out :user

    assert_no_difference("User.count") do
      post user_registration_path, params: {
        user: sign_up_params(terms_accepted: "0", privacy_accepted: "1")
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("auth.consents.terms_required", default: "Debes aceptar los Términos y condiciones para crear tu cuenta.")
    refute_includes response.body, I18n.t("auth.consents.privacy_required", default: "Debes aceptar la Política de privacidad para crear tu cuenta.")
  end

  test "sign up records legal acceptances with version, user and timestamp" do
    sign_out :user
    email = "legal-consents-#{SecureRandom.hex(4)}@example.com"

    assert_difference("User.count", 1) do
      assert_difference("UserConsent.count", 3) do
        assert_emails 1 do
          post user_registration_path, params: {
            user: sign_up_params(email: email)
          }
        end
      end
    end

    user = User.find_by!(email: email)
    legal = user.user_consents.legal.order(:consent_type)

    assert_equal %w[privacy terms], legal.map(&:consent_type)
    assert_equal [ "2026-11-07", "2026-11-06" ], legal.map(&:document_version)
    assert legal.all? { |consent| consent.occurred_at.present? }
    assert_equal [ user.id ], legal.map(&:user_id).uniq
  end

  test "sign up records declined marketing consent by default" do
    sign_out :user
    email = "declined-marketing-#{SecureRandom.hex(4)}@example.com"

    post user_registration_path, params: {
      user: sign_up_params(email: email, marketing_consent: "0")
    }

    marketing = User.find_by!(email: email).user_consents.marketing.first

    assert marketing.present?
    refute marketing.granted?
    assert marketing.occurred_at.present?
  end

  test "sign up records granted marketing consent when selected" do
    sign_out :user
    email = "granted-marketing-#{SecureRandom.hex(4)}@example.com"

    post user_registration_path, params: {
      user: sign_up_params(email: email, marketing_consent: "1")
    }

    marketing = User.find_by!(email: email).user_consents.marketing.first

    assert marketing.present?
    assert marketing.granted?
    assert marketing.occurred_at.present?
  end

  test "sign up ignores an admin parameter" do
    sign_out :user

    assert_difference("User.count") do
      assert_emails 1 do
        post user_registration_path, params: {
          user: sign_up_params(
            name: "Sneaky Admin",
            email: "sneaky-admin@example.com",
            admin: true
          )
        }
      end
    end

    refute User.find_by(email: "sneaky-admin@example.com").admin?
  end

  test "profile update ignores an admin parameter" do
    put user_registration_path, params: {
      user: {
        name: @user.name,
        email: @user.email,
        password: "",
        password_confirmation: "",
        current_password: "",
        admin: true
      }
    }

    assert_redirected_to root_path
    refute @user.reload.admin?
  end

  test "email change without the current password is rejected" do
    put user_registration_path, params: {
      user: {
        name: @user.name,
        email: "new-email@example.com",
        password: "",
        password_confirmation: "",
        current_password: ""
      }
    }

    assert_response :unprocessable_entity
    @user.reload
    assert_equal "registrations_ctrl_test@example.com", @user.email
  end

  test "email change with the current password is queued for confirmation" do
    put user_registration_path, params: {
      user: {
        name: @user.name,
        email: "new-email@example.com",
        password: "",
        password_confirmation: "",
        current_password: "password123"
      }
    }

    assert_redirected_to root_path
    @user.reload
    assert_equal "registrations_ctrl_test@example.com", @user.email
    assert_equal "new-email@example.com", @user.unconfirmed_email
  end

  private

  def sign_up_params(overrides = {})
    {
      name: "Consent User",
      email: "consent-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      terms_accepted: "1",
      privacy_accepted: "1"
    }.merge(overrides)
  end
end

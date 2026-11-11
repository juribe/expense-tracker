# frozen_string_literal: true

require "application_system_test_case"

# El botón "Importar Plantillas" de los listados recurrentes queda visible
# pero bloqueado para usuarios gratuitos; el clic abre el modal Premium.
class ImportTemplatesPremiumLockTest < ApplicationSystemTestCase
  setup do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    @user = User.create!(
      name: "Import Premium User",
      email: "import_premium_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @user.confirm
    grant_expired_membership(@user)
  end

  test "free users open the premium modal from the locked import action" do
    sign_in @user
    visit monthly_expenses_path

    assert_locked_import_action
  end

  test "free users open the premium modal from monthly incomes" do
    sign_in @user
    visit monthly_incomes_path

    assert_locked_import_action
  end

  private

  def assert_locked_import_action
    button = find("[data-testid='import-templates-locked']")
    assert_includes button.text, "Importar Plantillas"
    assert_includes button.text, "PREMIUM"
    assert_selector "[data-testid='import-templates-locked'] i.ti-lock"

    button.click

    assert_selector "#importPremiumModal.show"
    wait_for_modal_transition("#importPremiumModal")

    within("#importPremiumModal") do
      assert_text "Importar plantillas es Premium"
      assert_selector "a[href='#{plans_path}']", text: /Conocer Premium/
    end
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end

  def grant_expired_membership(user)
    membership_type = PaymentEngine::MembershipType.create!(
      name: "Import Premium Test",
      code: "IMPORT_PREMIUM_#{SecureRandom.hex(6)}",
      status: "active"
    )
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: membership_type,
      status: "expired",
      source: "purchase",
      starts_at: 2.months.ago,
      expires_at: 1.day.ago
    )
  end
end

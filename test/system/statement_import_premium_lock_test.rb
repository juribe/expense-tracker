# frozen_string_literal: true

require "application_system_test_case"

# El botón "Importar extracto" del formulario de pagos de deudas queda visible
# pero bloqueado para usuarios gratuitos; el clic abre el modal Premium.
class StatementImportPremiumLockTest < ApplicationSystemTestCase
  setup do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    @user = User.create!(
      name: "Statement Premium User",
      email: "statement_premium_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @user.confirm
    grant_expired_membership(@user)
    @card = @user.money_sources.create!(name: "Visa Premium", kind: "credit_card", starting_balance: 0)
    @card.create_credit_account!(principal_amount: 100_000, outstanding_balance: 100_000)
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 1_000_000)
    @category = Category.create!(name: "Compras", user: @user, category_type: "expense")
    @expense = Expense.create!(
      user: @user, amount: 100_000, description: "Compra", date: Date.current,
      kind: "expense", source: "manual", category: @category, money_source: @account
    )
  end

  test "free users open the premium modal from the locked statement import action" do
    sign_in @user
    visit new_money_source_payment_path(@card, expense_id: @expense.id)

    assert_locked_statement_action
  end

  test "free users open the premium modal from the debt show page" do
    sign_in @user
    visit money_source_path(@card)
    find("#source-tab-pagos-btn").click
    assert_selector "#source-tab-pagos.show.active"

    assert_locked_statement_action
  end

  private

  def assert_locked_statement_action
    button = find("[data-testid='statement-import-locked']")
    assert_includes button.text, "Importar extracto"
    assert_includes button.text, "PREMIUM"
    assert_selector "[data-testid='statement-import-locked'] i.ti-lock"

    button.click

    assert_selector "#statementImportPremiumModal.show"
    wait_for_modal_transition("#statementImportPremiumModal")

    within("#statementImportPremiumModal") do
      assert_text "Importar extractos es Premium"
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
      name: "Statement Premium Test",
      code: "STATEMENT_PREMIUM_#{SecureRandom.hex(6)}",
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

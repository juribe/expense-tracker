# frozen_string_literal: true

require "application_system_test_case"

class ExpenseCandidatesBulkBarTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Candidatos Bulk User", email: "candidatos_bulk@example.com", password: "password123")
    @user.confirm
    ExpenseCandidate.create!(
      user: @user, source: "gmail", status: "needs_review",
      amount: 45_000, date: Date.current, description: "PRICESMART COLOMBIA"
    )
  end

  test "la barra en lote aparece al seleccionar un candidato" do
    sign_in @user
    visit expense_candidates_path

    assert_selector "[data-testid='bulk-bar']", visible: false

    find(".row-check").check

    assert_selector "[data-testid='bulk-bar']", visible: true
    assert_text "1 seleccionados"
    assert_selector "[data-testid='bulk-confirm']:not([disabled])", visible: true
  end

  test "la barra en lote se oculta y deshabilita las acciones al desmarcar" do
    sign_in @user
    visit expense_candidates_path

    find(".row-check").check
    assert_selector "[data-testid='bulk-bar']", visible: true

    find(".row-check").uncheck

    assert_selector "[data-testid='bulk-bar']", visible: false
    assert find("[data-testid='bulk-confirm']", visible: :all).disabled?
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

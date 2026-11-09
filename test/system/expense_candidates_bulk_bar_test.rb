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
    assert_text "1 seleccionado"
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

  test "la barra en lote ofrece las cuatro acciones y permite limpiar la selección" do
    sign_in @user
    visit expense_candidates_path

    find(".row-check").check

    within "[data-testid='bulk-bar']" do
      assert_selector "[data-testid='bulk-category']", text: /Cambiar categoría/i
      assert_selector "[data-testid='bulk-source']", text: /Cambiar fuente/i
      assert_selector "[data-testid='bulk-confirm']", text: /Confirmar seleccionados/i
      assert_selector "[data-testid='bulk-discard']", text: /Descartar seleccionados/i
    end

    find("#bulkClearSelection").click

    assert_selector "[data-testid='bulk-bar']", visible: false
    assert_no_checked_field(class: "row-check")
  end

  test "el encabezado selecciona todas las filas visibles" do
    ExpenseCandidate.create!(
      user: @user, source: "gmail", status: "needs_review",
      amount: 18_000, date: Date.current, description: "SEGUNDO CANDIDATO"
    )
    sign_in @user
    visit expense_candidates_path

    select_all = page.has_selector?("#selectAll", visible: true) ? find("#selectAll") : find("#selectAllMobile")
    select_all.check

    assert_text "2 seleccionados"
    assert_selector "[data-testid='candidate-row'] .row-check:checked", count: 2, visible: :all
  end

  test "cambiar categoría abre el modal de categoría y no el de confirmación" do
    sign_in @user
    visit expense_candidates_path

    find(".row-check").check
    find("[data-testid='bulk-category']").click

    assert_selector "#bulkCategoryModal.show", wait: 5
    wait_for_modal_transition("#bulkCategoryModal")
    assert_selector "form#bulkCategoryForm select#bulkCategorySelect", visible: :all
    assert_no_selector "#bulkConfirmModal.show"
    assert_no_selector "#bulkCategoryModal .category-picker__feedback", visible: true

    find("#bulkCategoryForm button[type='submit']").click

    assert_selector "#bulkCategoryModal .category-picker__feedback", visible: true,
                                                                   text: /Elige una categoría/
  end

  test "cambiar categoría en lote conserva la selección tras recargar" do
    Category.create!(user: @user, name: "Mercado UI", is_default: false, category_type: "expense")
    sign_in @user
    visit expense_candidates_path

    find(".row-check").check
    find("[data-testid='bulk-category']").click
    wait_for_modal_transition("#bulkCategoryModal")
    fill_in "bulkCategorySelect_search", with: "Mercado UI"
    find("#bulkCategorySelect_listbox [role='option']", text: "Mercado UI").click
    find("#bulkCategoryForm button[type='submit']").click

    assert_selector "[data-testid='bulk-bar']", visible: true
    assert_text "1 seleccionado"
    assert_selector "[data-testid='candidate-row'] .row-check:checked", count: 1, visible: :all
    assert_selector "[data-testid='candidate-row']", text: /Mercado UI/, visible: :all
  end

  test "la pestaña de descartados muestra su estado vacío sin ocultar las pestañas" do
    sign_in @user
    visit expense_candidates_path(status: "discarded")

    assert_selector "[data-testid='candidates-empty']", text: /Sin candidatos descartados/
    assert_selector "[data-testid='pending-tab']"
    assert_selector "[data-testid='discarded-tab']"
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

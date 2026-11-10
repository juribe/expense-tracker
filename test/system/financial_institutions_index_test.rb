# frozen_string_literal: true

require "application_system_test_case"

# The entities hub filters the server-rendered cards in the browser and keeps
# the Bootstrap grid responsive (three columns on desktop, two on tablet and
# one on mobile) without horizontal overflow.
class FinancialInstitutionsIndexTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    page.current_window.resize_to(1400, 1000)

    @user = User.create!(name: "Entities UI", email: "entities-ui-system@example.com",
                         password: "password123")
    @user.confirm

    @user.custom_financial_institutions.create!(name: "Wise", institution_type: "digital_bank")
    @user.custom_financial_institutions.create!(name: "Cooperativa ejemplo", institution_type: "other")
    @user.custom_financial_institutions.create!(name: "Banco local", institution_type: "bank")
  end

  test "search filters the user's entities by name without reloading" do
    sign_in
    visit financial_institutions_path

    assert_selector "[data-financial-institution-card]", count: 3
    page.execute_script("window.entitiesFilterMarker = 'alive'")

    fill_in "financial-institution-search", with: "wise"

    assert_selector "[data-financial-institution-card][data-entity-name='Wise']", visible: true
    assert_no_selector "[data-financial-institution-card][data-entity-name='Cooperativa ejemplo']", visible: true
    assert_no_selector "[data-financial-institution-card][data-entity-name='Banco local']", visible: true

    fill_in "financial-institution-search", with: "zzz-no-entity"

    assert_selector "[data-financial-institutions-no-results]", visible: true

    fill_in "financial-institution-search", with: ""

    assert_selector "[data-financial-institution-card]", count: 3
    assert_no_selector "[data-financial-institutions-no-results]", visible: true
    assert_equal "alive", page.evaluate_script("window.entitiesFilterMarker")
  end

  test "the card grid uses three, two and one columns by viewport" do
    sign_in
    visit financial_institutions_path

    assert_equal 1, unique_card_rows(1400), "escritorio debe mostrar tres columnas"
    assert_equal 2, unique_card_rows(900), "tablet debe mostrar dos columnas"
    assert_equal 3, unique_card_rows(500), "móvil debe mostrar una columna"

    refute horizontal_overflow?, "la cuadrícula no debe desbordarse horizontalmente"
  end

  private

  def unique_card_rows(width)
    page.current_window.resize_to(width, 900)
    page.evaluate_script(<<~JS)
      (() => {
        const tops = Array.from(document.querySelectorAll("[data-financial-institution-card]"))
          .filter((card) => !card.hidden)
          .map((card) => Math.round(card.getBoundingClientRect().top));
        return new Set(tops).size;
      })()
    JS
  end

  def horizontal_overflow?
    page.evaluate_script(
      "document.documentElement.scrollWidth > document.documentElement.clientWidth + 1"
    )
  end

  def sign_in
    visit new_user_session_path
    fill_in "user_email", with: @user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

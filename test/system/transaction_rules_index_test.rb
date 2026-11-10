# frozen_string_literal: true

require "application_system_test_case"

# La búsqueda y los filtros de estado de las reglas automáticas trabajan en el
# cliente: el listado se reduce sin recargar la página y ambos controles se
# combinan. También se verifica que el estado vacío aparezca al no haber
# coincidencias.
class TransactionRulesIndexTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    page.current_window.resize_to(1400, 1000)

    @user = User.create!(name: "Rules User", email: "rules-index-#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    @user.confirm

    market = Category.create!(user: @user, name: "Mercado", category_type: "expense", is_default: false)
    transport = Category.create!(user: @user, name: "Transporte", category_type: "expense", is_default: false)

    @user.transaction_rules.create!(name: "Mercado semanal", merchant_contains: "sao 094",
                                    category: market, enabled: true)
    @user.transaction_rules.create!(name: "Tanqueo", merchant_contains: "eds santa maria",
                                    category: transport, enabled: false)
  end

  test "search and status filters combine without reloading the page" do
    sign_in
    visit transaction_rules_path
    assert_equal [ "Mercado semanal", "Tanqueo" ], visible_rule_names

    page.execute_script("window.rulesFilterMarker = 'alive'")

    fill_in "rules-search", with: "sao"
    assert_equal [ "Mercado semanal" ], visible_rule_names

    fill_in "rules-search", with: ""
    find("[data-testid='rules-filter-disabled']").click
    assert_equal [ "Tanqueo" ], visible_rule_names

    fill_in "rules-search", with: "sao"
    assert_equal [], visible_rule_names
    assert_selector "[data-testid='rules-no-results']", visible: true

    find("[data-testid='rules-filter-all']").click
    assert_equal [ "Mercado semanal" ], visible_rule_names
    assert_no_selector "[data-testid='rules-no-results']", visible: true

    assert_equal "alive", page.evaluate_script("window.rulesFilterMarker")
  end

  test "cards and controls stay inside the mobile viewport" do
    sign_in
    page.current_window.resize_to(500, 900)
    visit transaction_rules_path

    layout = page.evaluate_script(<<~JS)
      (() => {
        const viewport = document.documentElement.clientWidth;
        const targets = document.querySelectorAll(
          "[data-testid='rules-search'], .rules-filter, [data-testid='rule-card'], .rules-condition-type, .rules-match-value, .rules-result-pill, .rules-card-actions .btn"
        );
        const overflowing = Array.from(targets).filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.left < -1 || rect.right > viewport + 1;
        }).length;

        return {
          overflowing,
          scrollsHorizontally: document.documentElement.scrollWidth > viewport + 1
        };
      })()
    JS

    assert_equal 0, layout["overflowing"], "las tarjetas y controles deben caber en móvil"
    refute layout["scrollsHorizontally"], "la página no debe requerir scroll horizontal en móvil"
  end

  private

  def visible_rule_names
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-testid='rule-card']"))
        .filter((card) => getComputedStyle(card).display !== "none")
        .map((card) => card.dataset.ruleName)
    JS
  end

  def sign_in
    visit new_user_session_path
    fill_in "user_email", with: @user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

# frozen_string_literal: true

require "application_system_test_case"

# The available-cycle report exposes the pending expenses of the current cycle
# with client-side search, due-date sorting and a values/percentage switch.
class AvailableCycleReportTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @user = User.create!(name: "Available Cycle UI", email: "available_cycle_ui@example.com", password: "password123")
    @user.confirm
    @category = Category.create!(user: @user, name: "Servicios", category_type: "expense", is_default: false)
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true, starting_balance: 5_000_000)
    create_template("Internet", 28, 100_000)
    create_template("Arriendo", 20, 1_500_000)
    create_template("Sin fecha", nil, 320_000)
  end

  test "search sort and percentage switch use the real pending rows" do
    sign_in @user
    visit reports_available_cycle_path

    assert_selector "h1", text: "Disponible del ciclo"
    assert_selector "[data-testid='pending-expense-row']", count: 3

    find("[data-available-cycle-search]").set("Internet")
    visible_rows = page.evaluate_script(
      "Array.from(document.querySelectorAll('[data-available-cycle-row]')).filter((row) => !row.hidden).map((row) => row.dataset.search)"
    )
    assert_equal [ "Internet Servicios" ], visible_rows
    assert_text "1 gasto pendiente"

    find("[data-available-cycle-search]").set("")
    assert_text "3 gastos pendientes"

    find("button[data-available-cycle-sort='due_date']").click
    assert_equal "Fecha inversa", find("button[data-available-cycle-sort='due_date'] [data-available-cycle-sort-label]").text
    order = page.evaluate_script(
      "Array.from(document.querySelectorAll('[data-available-cycle-row]')).map((row) => row.dataset.dueDate || 'none')"
    )
    assert_equal "none", order.last
    dated_order = order[0..-2]
    assert_equal dated_order.sort.reverse, dated_order

    find("button[data-available-cycle-sort='missing']").click
    assert_equal "Mayor faltante", find("button[data-available-cycle-sort='missing'] [data-available-cycle-sort-label]").text
    missing_order = page.evaluate_script(
      "Array.from(document.querySelectorAll('[data-available-cycle-row]')).map((row) => parseFloat(row.dataset.missing))"
    )
    assert_equal missing_order.sort.reverse, missing_order

    page.execute_script(%q{document.querySelector("[data-available-cycle-mode='percent']").click()})
    assert_selector "[data-available-cycle-mode='percent'].is-active"
    assert_equal true, page.evaluate_script("document.querySelector('[data-available-cycle-values]').hidden")
    assert_equal false, page.evaluate_script("document.querySelector('[data-available-cycle-percent]').hidden")
  end

  private

  def create_template(description, payment_day, amount)
    @user.recurring_templates.create!(
      category: @category, kind: "expense", description: description,
      amount: amount, frequency: "monthly", source: "manual",
      payment_day: payment_day, money_source: @account
    )
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "Correo electrónico", with: user.email, match: :first
    fill_in "Contraseña", with: "password123", match: :first
    click_button I18n.t("auth.sign_in")
  end
end

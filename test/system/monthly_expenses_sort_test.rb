# frozen_string_literal: true

require "application_system_test_case"

# La tabla de gastos recurrentes ordena en el cliente: al pulsar un encabezado
# no debe recargarse la página ni reemplazarse la tabla por una navegación de
# Turbo. Los enlaces siguen funcionando como fallback sin JavaScript.
class MonthlyExpensesSortTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Sort User", email: "monthly_sort@example.com", password: "password123")
    @user.confirm
    services = Category.create!(user: @user, name: "Servicios", category_type: "expense", is_default: false)
    shopping = Category.create!(user: @user, name: "Compras", category_type: "expense", is_default: false)

    @user.recurring_templates.create!(
      category: services, kind: "expense", amount: 90_000, frequency: "monthly",
      source: "manual", description: "Agua", payment_day: 5
    )
    @user.recurring_templates.create!(
      category: shopping, kind: "expense", amount: 10_000, frequency: "monthly",
      source: "manual", description: "Zapato", payment_day: 10
    )
  end

  test "sorting by amount reorders rows without reloading the page" do
    page.current_window.resize_to(1400, 1000)
    sign_in
    visit monthly_expenses_path

    assert_equal [ "Agua", "Zapato" ], rendered_descriptions

    page.execute_script(
      "window.recurringSortMarker = 'alive';" \
      "window.recurringSortTable = document.querySelector('[data-testid=\\'recurring-table\\']');"
    )

    find("[data-recurring-sort-column='amount']").click

    assert_equal "alive", page.evaluate_script("window.recurringSortMarker")
    assert page.evaluate_script("window.recurringSortTable && window.recurringSortTable.isConnected")
    assert_equal [ "Zapato", "Agua" ], rendered_descriptions
    assert_includes page.current_url, "sort=amount"
    assert_includes page.current_url, "dir=asc"
    assert_equal "amount", find("input[name='sort']", visible: :all).value
    assert_equal "asc", find("input[name='dir']", visible: :all).value

    find("[data-recurring-sort-column='amount']").click

    assert_equal "alive", page.evaluate_script("window.recurringSortMarker")
    assert page.evaluate_script("window.recurringSortTable && window.recurringSortTable.isConnected")
    assert_equal [ "Agua", "Zapato" ], rendered_descriptions
    assert_includes page.current_url, "dir=desc"
    assert_equal "desc", find("input[name='dir']", visible: :all).value
  end

  private

  def rendered_descriptions
    all("tr[data-testid='recurring-row']").map { |row| row["data-description"] }
  end

  def sign_in
    visit new_user_session_path
    fill_in "user_email", with: @user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

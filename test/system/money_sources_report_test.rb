# frozen_string_literal: true

require "application_system_test_case"

# The redesigned money-sources report keeps its drill-down and adds local
# interactions: collapse/expand, source search and row sorting.
class MoneySourcesReportSystemTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Money Sources System", email: "money_sources_system@example.com",
                         password: "password123")
    @user.confirm
    @category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta de Ahorros", kind: "account", active: true,
                                           starting_balance: 10_000_000)
    @card = @user.money_sources.create!(name: "Tarjeta Visa Infinite", kind: "credit_card", active: true)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true,
                                         starting_balance: 1_000_000)
    @user.expenses.create!(amount: -1_000_000, date: Date.current, category: @category,
                           money_source: @account, description: "market")
    @user.expenses.create!(amount: -500_000, date: Date.current, category: @category,
                           money_source: @card, description: "card purchase")
    @user.expenses.create!(amount: -100_000, date: Date.current, category: @category,
                           money_source: @cash, description: "cash")
  end

  test "expands, searches and sorts the source detail without recalculating totals" do
    sign_in @user
    visit reports_money_sources_path(period: "this_month")

    assert_selector "[data-testid=money-sources-summary]"
    assert_selector "tr[data-money-source-row]", text: @account.name

    accounts_group = find("tr[data-money-source-group]", text: "Cuentas")
    within(accounts_group) { find("[data-money-source-toggle]").click }

    assert_no_selector "tr[data-money-source-row]", text: @account.name
    assert_selector "tr[data-money-source-group]", text: "Cuentas"

    within(accounts_group) { find("[data-money-source-toggle]").click }
    assert_selector "tr[data-money-source-row]", text: @account.name

    fill_in "Buscar fuente...", with: "Visa"
    assert_selector "tr[data-money-source-row]", text: @card.name
    assert_no_selector "tr[data-money-source-row]", text: @account.name

    fill_in "Buscar fuente...", with: ""
    find("[data-money-source-sort]").select("Nombre A-Z")
    labels = all("tr[data-money-source-group]").map(&:text)
    assert_includes labels.first, "Cuentas"
    assert_includes labels.last, "Tarjetas de crédito"
  end

  test "clicking a source opens its transactions while group controls stay local" do
    sign_in @user
    visit reports_money_sources_path(period: "this_month")

    report_url = current_url
    accounts_group = find("tr[data-money-source-group]", text: "Cuentas")
    accounts_group.click

    assert_equal report_url, current_url, "group controls must not navigate"
    assert_selector "tr[data-money-source-group]", text: "Cuentas"

    within(accounts_group) { find("[data-money-source-toggle]").click }
    card_row = find("tr[data-money-source-row]", text: @card.name)
    card_row.click

    assert_includes current_url, "/reports/transactions"
    assert_includes current_url, "money_source_id=#{@card.id}"
    assert_includes current_url, "period=this_month"
    assert_selector "[data-testid=reports-transactions-table]"
    assert_text "$500.000"
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "Correo electrónico", with: user.email, match: :first
    fill_in "Contraseña", with: "password123", match: :first
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

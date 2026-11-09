# frozen_string_literal: true

require "application_system_test_case"

# The category report keeps its existing drill-down: both the table rows and
# the distribution bars open the full transactions report for that category.
class CategoryReportNavigationTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Category Navigation", email: "category_navigation_ui@example.com",
                         password: "password123")
    @user.confirm
    @user.update!(financial_cycle_start_day: 20)
    @bank = @user.money_sources.create!(name: "Cuenta principal", kind: "account", active: true,
                                        starting_balance: 20_000_000)
    @categories = %w[Vivienda Educación Transporte Alimentación Salud Ocio Servicios Compras].index_with do |name|
      Category.create!(user: @user, name: name, category_type: "expense", is_default: false,
                       icon: "ti-tag")
    end
    @cycle = PayCycle.current(@user)
    create_expenses
  end

  test "table rows and distribution bars open the selected category modal" do
    sign_in @user
    visit reports_by_category_path

    assert_selector "[data-testid=category-summary]"
    assert_selector "[data-testid=category-table] tbody tr", count: 8
    assert_selector ".category-distribution-row", count: 7
    assert_selector "#reportTransactionsModal", visible: :all
    assert_no_selector "#reportTransactionsModal.show"

    row = find("tr[data-transactions-modal-url]", text: "Educación")
    row.find("td:nth-child(2)").click

    assert_selector "#reportTransactionsModal.show", wait: 10
    within("#reportTransactionsModal") do
      assert_selector "[data-testid=report-transactions-modal-content]", wait: 10
      assert_text "Educación"
      assert_no_text "Vivienda"
    end
    assert_match %r{/reports/by_category}, page.current_path

    find("#reportTransactionsModal .btn-close").click
    assert_no_selector "#reportTransactionsModal.show", wait: 5

    find("a.category-distribution-row", text: "Transporte").click

    assert_selector "#reportTransactionsModal.show", wait: 10
    within("#reportTransactionsModal") do
      assert_selector "[data-testid=report-transactions-modal-content]", wait: 10
      assert_text "Transporte"
      assert_no_text "Educación"
    end
    assert_match %r{/reports/by_category}, page.current_path
  end

  private

  def create_expenses
    [ [ "Vivienda", 2_450_000 ], [ "Educación", 1_120_000 ], [ "Transporte", 640_000 ],
      [ "Alimentación", 530_000 ], [ "Salud", 310_000 ], [ "Ocio", 185_000 ],
      [ "Servicios", 120_000 ], [ "Compras", 80_000 ] ].each_with_index do |(name, amount), index|
      @user.expenses.create!(category: @categories[name], money_source: @bank, amount: -amount,
                             date: @cycle.starts + (index + 1).days, description: name)
    end
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "Correo electrónico", with: user.email, match: :first
    fill_in "Contraseña", with: "password123", match: :first
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

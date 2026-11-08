# frozen_string_literal: true

require "application_system_test_case"

# Clicking a category row must open that category's transactions in the shared
# report modal instead of navigating away from the category report.
class CategorySpendingDrillDownTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(name: "Category UI", email: "category_spending_ui@example.com", password: "password123")
    @user.confirm
    @food = Category.create!(user: @user, name: "Café", category_type: "expense")
    @transport = Category.create!(user: @user, name: "Transporte", category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true, starting_balance: 1_000_000)
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 3), category: @food,
                           money_source: @bank, description: "Café del día")
    @user.expenses.create!(amount: -200_000, date: Date.new(2026, 9, 4), category: @transport,
                           money_source: @bank, description: "Taxi")
  end

  test "clicking a category row opens its transactions in a modal" do
    sign_in @user
    visit reports_by_category_path(period: "custom", start_date: "2026-09-01", end_date: "2026-09-30")

    assert_selector "tr[data-transactions-modal-url]", text: "Café"
    row = find("tr[data-transactions-modal-url]", text: "Café")
    # The sticky report shell can intercept Selenium's hit-tested click in small
    # headless viewports; dispatch the row click directly to exercise the handler.
    page.execute_script("arguments[0].click()", row)

    assert_selector "[data-testid=report-transactions-modal].show"
    assert_selector "[data-testid=reports-transactions-table]"
    assert_text "Café del día"
    assert_no_text "Taxi"
    assert_equal reports_by_category_path, page.current_path
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

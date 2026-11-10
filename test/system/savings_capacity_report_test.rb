# frozen_string_literal: true

require "application_system_test_case"

# The savings-capacity report is a read-only projection: the basic reserve,
# the previous-cycle reference and the selected cycle update the visible
# result without a page reload (except the cycle selector, which navigates).
class SavingsCapacityReportTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @user = User.create!(name: "Savings Capacity UI", email: "savings_capacity_ui@example.com",
                         password: "password123")
    @user.confirm
    @user.update!(financial_cycle_start_day: 20)
    @expense_category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true,
                                        starting_balance: 10_000_000)

    @user.recurring_templates.create!(category: @income_category, kind: "income", amount: 10_000_000,
                                      frequency: "monthly", payment_day: 10, active: true,
                                      description: "Salary", money_source: @bank)
    @user.recurring_templates.create!(category: @expense_category, kind: "expense", amount: 3_000_000,
                                      frequency: "monthly", payment_day: 10, active: true,
                                      description: "Rent", money_source: @bank)
    @user.expenses.create!(amount: -1_550_000, date: Date.new(2026, 10, 1),
                           category: @expense_category, money_source: @bank, description: "variable")
  end

  test "toggles and percentage update in place and the cycle selector keeps the closed reference" do
    travel_to Date.new(2026, 11, 7) do
      sign_in @user
      visit reports_savings_capacity_path

      assert_selector "h1", text: "Capacidad de ahorro"
      assert_selector "[data-testid='savings-capacity-result']", text: "$2.450.000"
      assert_includes find("a[data-savings-capacity-goal-link]")["href"], "target_amount=2450000"

      page.execute_script("document.querySelector('[data-savings-capacity-basic-toggle]').click()")
      assert_selector "[data-testid='savings-capacity-result']", text: "$5.450.000"
      assert_includes find("a[data-savings-capacity-goal-link]")["href"], "target_amount=5450000"

      page.execute_script("document.querySelector('[data-savings-capacity-basic-toggle]').click()")
      page.execute_script(
        "var r=document.querySelector('input[data-savings-capacity-percentage]');" \
        "r.value=50;r.dispatchEvent(new Event('input',{bubbles:true}));"
      )
      assert_selector "[data-testid='savings-capacity-result']", text: "$450.000"

      page.execute_script("document.querySelector('[data-savings-capacity-history-toggle]').click()")
      assert_selector "[data-testid='savings-capacity-result']", text: "$2.000.000"

      page.execute_script("document.querySelector('[data-savings-capacity-history-toggle]').click()")
      page.execute_script(
        "var r=document.querySelector('input[data-savings-capacity-percentage]');" \
        "r.value=30;r.dispatchEvent(new Event('input',{bubbles:true}));"
      )
      assert_selector "[data-testid='savings-capacity-result']", text: "$2.450.000"

      second = Reports::SavingsCapacity.future_cycles(@user)[1]
      option = find("select[name=cycle] option[value='#{second.starts.iso8601}']")
      find("select[name=cycle]").select(option.text)

      assert_selector "[data-testid='savings-capacity-result']", text: "$2.450.000"
      assert_selector "[data-testid='savings-capacity-previous-variable']", text: "$1.550.000"
      assert_text "Último ciclo cerrado: Sep 20 – Oct 19"
      assert_text "Usamos el último ciclo cerrado para no estimar con datos parciales del ciclo en curso"
    end
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

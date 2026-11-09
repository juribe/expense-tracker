# frozen_string_literal: true

require "application_system_test_case"

# Las barras de progreso deben tener altura y ancho reales: no basta con que
# el HTML incluya la clase o el atributo de estilo.
class ProgressBarsTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(name: "Progress Bars UI", email: "progress_bars_ui@example.com",
                         password: "password123")
    @user.confirm
    @category = Category.create!(user: @user, name: "Comida UI", category_type: "expense", is_default: false)
    @account = MoneySource.create!(user: @user, name: "Cuenta UI", kind: "account",
                                   starting_balance: 5_000_000)
    @pocket = MoneySource.create!(user: @user, name: "Bolsillo UI", kind: "pocket",
                                  starting_balance: 1_000_000)
    @goal = Goal.create!(user: @user, pocket: @pocket, name: "Meta UI", target_amount: 1_000_000)
    GoalAllocation.create!(financial_goal: @goal, pocket: @pocket, amount: 400_000, date: Date.current)
    Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000)
    Expense.create!(user: @user, category: @category, amount: -400_000, date: Date.current,
                    description: "Gasto UI", money_source: @account)

    sign_in @user
  end

  test "budget progress bar renders with real width and height" do
    visit budgets_path

    assert_selector "[data-testid='budget-progress'] .budget-progress-bar"

    heights = page.evaluate_script(<<~JS)
      (() => {
        const track = document.querySelector("[data-testid='budget-progress']");
        const bar = document.querySelector("[data-testid='budget-progress'] .budget-progress-bar");
        return { track: track.getBoundingClientRect().width, bar: bar.getBoundingClientRect() };
      })()
    JS

    assert_operator heights["bar"]["height"], :>, 0, "budget bar has no rendered height"
    assert_operator heights["bar"]["width"], :>, 0, "budget bar has no rendered width"
    assert_in_delta heights["track"] * 0.4, heights["bar"]["width"], 6
  end

  test "pocket distribution bar renders with real width and height" do
    visit money_sources_pockets_path

    assert_selector "[data-testid='pocket-card-allocated-bar']"

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const track = document.querySelector(".pocket-card-bar");
        const allocated = document.querySelector("[data-testid='pocket-card-allocated-bar']");
        const free = document.querySelector("[data-testid='pocket-card-free-bar']");
        return {
          track: track.getBoundingClientRect().width,
          allocated: allocated.getBoundingClientRect(),
          free: free.getBoundingClientRect()
        };
      })()
    JS

    assert_operator metrics["allocated"]["height"], :>, 0, "allocated bar has no rendered height"
    assert_operator metrics["allocated"]["width"], :>, 0, "allocated bar has no rendered width"
    assert_operator metrics["free"]["height"], :>, 0, "free bar has no rendered height"
    assert_operator metrics["free"]["width"], :>, 0, "free bar has no rendered width"
    assert_in_delta metrics["track"] * 0.4, metrics["allocated"]["width"], 6
    assert_in_delta metrics["track"] * 0.6, metrics["free"]["width"], 6
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
  end
end

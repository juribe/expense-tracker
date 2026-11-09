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

  test "goal progress track stays visible when there is no progress" do
    Goal.create!(user: @user, pocket: @pocket, name: "Meta sin avance", target_amount: 1_000_000)
    visit goals_path

    assert_selector "[data-testid='goal-card']", text: "Meta sin avance"

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const card = Array.from(document.querySelectorAll("[data-testid='goal-card']"))
          .find((element) => element.textContent.includes("Meta sin avance"));
        const track = card.querySelector("[data-testid='goal-card-progress']");
        const bar = track.querySelector(".progress-bar");
        return {
          width: track.getBoundingClientRect().width,
          height: track.getBoundingClientRect().height,
          background: getComputedStyle(track).backgroundColor,
          barWidth: bar.getBoundingClientRect().width
        };
      })()
    JS

    assert_operator metrics["width"], :>, 0, "goal progress track has no rendered width"
    assert_operator metrics["height"], :>, 0, "goal progress track has no rendered height"
    refute_equal "rgba(0, 0, 0, 0)", metrics["background"], "goal progress track is transparent"
    assert_in_delta 0, metrics["barWidth"], 1
  end

  test "assign to goal hint keeps contrast in dark mode" do
    visit goals_path

    find("[data-bs-target='#assign-to-goal-modal']").click
    wait_for_modal_transition("#assign-to-goal-modal")
    page.execute_script("document.documentElement.setAttribute('data-bs-theme', 'dark')")

    colors = page.evaluate_script(<<~JS)
      (() => {
        const modal = document.querySelector("#assign-to-goal-modal");
        const alert = modal.querySelector(".alert");
        const link = alert.querySelector("a");
        const pocket = modal.querySelector(".form-control");
        return {
          text: getComputedStyle(alert).color,
          background: getComputedStyle(alert).backgroundColor,
          link: getComputedStyle(link).color,
          pocketText: getComputedStyle(pocket).color,
          pocketBackground: getComputedStyle(pocket).backgroundColor
        };
      })()
    JS

    assert_channel_contrast colors["text"], colors["background"]
    assert_channel_contrast colors["link"], colors["background"]
    assert_channel_contrast colors["pocketText"], colors["pocketBackground"]
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

  def assert_channel_contrast(text_color, background_color)
    text_luma = relative_luminance(text_color)
    background_luma = relative_luminance(background_color)
    ratio = ([ text_luma, background_luma ].max + 0.05) / ([ text_luma, background_luma ].min + 0.05)

    assert_operator ratio, :>=, 4.5,
                    "expected readable contrast between #{text_color} and #{background_color}"
  end

  def relative_luminance(color)
    channels = color.scan(/\d+(?:\.\d+)?/).first(3).map(&:to_f).map do |channel|
      value = channel / 255.0
      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
  end
end

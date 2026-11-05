# frozen_string_literal: true

require "application_system_test_case"

class CategoryInsightsSystemTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @user = User.create!(name: "Insights UI", email: "insights_ui@example.com", password: "password123")
    @user.confirm
    @high = Category.create!(name: "Viajes UI", is_default: true, category_type: "expense",
                             suggested_savings_percentage: 10, savings_potential: "high", icon: "ti-plane")
    @medium = Category.create!(name: "Restaurantes UI", is_default: true, category_type: "expense",
                               suggested_savings_percentage: 10, savings_potential: "medium",
                               icon: "ti-chef-hat")
    @low = Category.create!(name: "Mercado UI", is_default: true, category_type: "expense",
                            suggested_savings_percentage: 5, savings_potential: "low",
                            icon: "ti-shopping-cart")
    @high.saving_tips.create!(title: "Reserva con anticipación", body: "Compara opciones con tiempo.",
                              active: true, position: 0)

    bank = @user.money_sources.create!(name: "Banco UI", kind: "account", active: true,
                                       starting_balance: 1_000_000_000)
    Expense.create!(user: @user, category: @high, money_source: bank, amount: -100_000,
                    date: Date.current, description: "Vuelo")
    Expense.create!(user: @user, category: @low, money_source: bank, amount: -200_000,
                    date: Date.current, description: "Mercado")

    sign_in @user
  end

  test "filters, searches, sorts and opens the category analysis" do
    visit category_insights_path

    assert_selector "[data-category-insights-item][data-category-name='Viajes UI']", visible: true
    assert_selector "[data-category-insights-item][data-category-name='Mercado UI']", visible: true
    assert_selector "[data-category-insights-item][data-category-name='Restaurantes UI']", visible: true

    click_button "Potencial alto"

    assert_selector "[data-category-insights-item][data-category-name='Viajes UI']", visible: true
    assert_no_selector "[data-category-insights-item][data-category-name='Mercado UI']", visible: true
    assert_no_selector "[data-category-insights-item][data-category-name='Restaurantes UI']", visible: true

    click_button "Todas"
    fill_in "Buscar categoría", with: "mercado"

    assert_selector "[data-category-insights-item][data-category-name='Mercado UI']", visible: true
    assert_no_selector "[data-category-insights-item][data-category-name='Viajes UI']", visible: true

    fill_in "Buscar categoría", with: ""
    find("select[data-category-insights-sort]").select("Mayor gasto")

    first_name = page.evaluate_script(
      "document.querySelector('[data-category-insights-list] [data-category-insights-item]:not([hidden])').dataset.categoryName"
    )
    assert_equal "Mercado UI", first_name

    within("[data-category-insights-item][data-category-name='Viajes UI']") do
      click_link "Ver análisis"
    end

    assert_text "Análisis de ahorro"
    assert_text "Viajes UI"
    assert_text "Reserva con anticipación"
  end

  test "opens expenses filtered by the selected category" do
    visit category_insight_path(@high)

    click_link "Ver gastos de esta categoría"

    assert_current_path expenses_path(category_id: @high.id)
    assert_text "Viajes UI"
  end

  test "renders the list and detail in a mobile viewport" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit category_insights_path

    assert_selector "[data-category-insights-item][data-category-name='Viajes UI']", visible: true

    visit category_insight_path(@high)

    assert_selector "[data-testid='category-insight-analysis']", visible: true
    assert_selector "[data-testid='category-insight-tips']", visible: true
    assert_text "Ver gastos de esta categoría"
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

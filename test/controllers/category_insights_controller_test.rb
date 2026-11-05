# frozen_string_literal: true

require "test_helper"

class CategoryInsightsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Insight User", email: "insight_ctrl@example.com", password: "password123")
    @other = User.create!(name: "Other", email: "insight_other@example.com", password: "password123")
    @category = Category.create!(name: "Insight Cat", is_default: true, category_type: "expense",
                                 suggested_savings_percentage: 15, savings_potential: "high", icon: "ti-plane")
    @tip = @category.saving_tips.create!(title: "Compara tarifas", body: "Revisa cargos.", active: true, position: 0)
    sign_in @user
  end

  test "GET insight renders for own/default category" do
    get category_insight_path(@category)
    assert_response :success
    assert_match @category.name, response.body
    assert_match "Compara tarifas", response.body
  end

  test "does not show inactive tips" do
    @category.saving_tips.create!(title: "Inactiva", body: "No mostrar", active: false, position: 1)
    get category_insight_path(@category)
    assert_response :success
    assert_no_match "Inactiva", response.body
  end

  test "redirects when category not accessible" do
    custom = Category.create!(name: "Custom", is_default: false, category_type: "expense", user: @other)
    get category_insight_path(custom)
    assert_redirected_to categories_path
  end

  test "GET index renders the opportunities header and explanatory note" do
    get category_insights_path

    assert_response :success
    assert_select "h1", text: "Ahorro por categoría"
    assert_includes response.body,
                    "Revisa qué categorías podrían ofrecerte margen para reducir gastos según tu actividad."
    assert_select "[data-testid='potential-note']" do
      assert_select "strong", text: "¿Cómo interpretar el potencial de ahorro?"
      assert_match "orientativas", response.body
    end
  end

  test "GET index renders summary cards from real data" do
    medium = Category.create!(name: "Medium Cat", is_default: true, category_type: "expense",
                              suggested_savings_percentage: 5, savings_potential: "medium")
    low = Category.create!(name: "Low Cat", is_default: true, category_type: "expense",
                           suggested_savings_percentage: 5, savings_potential: "low")

    expense_for(@category, amount: -300_000, date: Date.current.prev_month)
    expense_for(low, amount: -100_000, date: Date.current)

    categories = eligible_categories
    analyzed = categories.size
    potential = categories.count { |category| %w[high medium].include?(category.savings_potential) }
    limited = categories.count do |category|
      CategoryInsight.new(user: @user, category: category).call[:average_spending].blank?
    end

    get category_insights_path

    assert_response :success
    assert_select "[data-testid='stat-analyzed'] .ci-stat-value", text: analyzed.to_s
    assert_select "[data-testid='stat-potential'] .ci-stat-value", text: potential.to_s
    assert_select "[data-testid='stat-limited'] .ci-stat-value", text: limited.to_s
    assert_select "[data-testid='stat-potential']", text: /Con potencial por revisar/
    assert_select "[data-testid='stat-limited']", text: /Con historial limitado/
  end

  test "GET index renders category rows with database icon, potential and current cycle spending" do
    expense_for(@category, amount: -300_000, date: Date.current)

    get category_insights_path

    assert_response :success
    assert_select "[data-category-insights-item][data-category-name='Insight Cat']" do
      assert_select "i.ti-plane"
      assert_select ".ci-level", text: "Potencial alto"
      assert_select ".ci-amount", text: /300\.000/
      assert_select ".ci-meta", text: /Actividad registrada en el ciclo actual/
      assert_select "a", text: /Ver análisis/
    end
  end

  test "GET index renders search, sort and potential filters" do
    get category_insights_path

    assert_response :success
    assert_select "input[data-category-insights-search][placeholder='Buscar categoría']"
    assert_select "select[data-category-insights-sort]" do
      assert_select "option", count: 4
    end
    assert_select "[data-category-insights-filter='all']", text: /Todas/
    assert_select "[data-category-insights-filter='high']", text: /Potencial alto/
    assert_select "[data-category-insights-filter='medium']", text: /Potencial medio/
    assert_select "[data-category-insights-filter='low']", text: /Potencial bajo/
  end

  test "GET index shows zero current spending for a category with completed-cycle history" do
    expense_for(@category, amount: -300_000, date: Date.current.prev_month)

    get category_insights_path

    assert_response :success
    assert_select "[data-category-insights-item][data-category-name='Insight Cat']" do
      assert_select ".ci-meta", text: /Promedio de 1 ciclo con actividad/
      assert_select ".ci-amount", text: /#{Regexp.escape(MoneyFormat.currency(0))}/
      assert_select ".ci-amount small", text: "Sin gastos este ciclo"
    end
  end

  test "GET insight renders header with icon, name, description, cycle and back link" do
    get category_insight_path(@category)
    cycle = PayCycle.current(@user)

    assert_response :success
    assert_select "[data-testid='category-insight-header']" do
      assert_select "i.ti-plane"
      assert_select "h1", text: "Insight Cat"
      assert_select "p", text: /Análisis de esta categoría/
    end
    assert_includes response.body, cycle.label
    assert_includes response.body, cycle.range_label
    assert_select "a[href='#{category_insights_path}']", text: /Volver a categorías/
  end

  test "GET insight shows analysis metrics when there is history" do
    expense_for(@category, amount: -300_000, date: Date.current.prev_month)

    get category_insight_path(@category)

    assert_response :success
    assert_select "h2", text: "Análisis de ahorro"
    assert_select "[data-testid='category-insight-potential']", text: /Alto/
    assert_select "[data-testid='metric-average']", text: /300\.000/
    assert_select "[data-testid='metric-reduction']", text: /15%/
    assert_select "[data-testid='metric-savings']", text: /45\.000/
    assert_select "[data-testid='metric-current']", text: /Sin gastos en el ciclo/
    assert_select "[data-testid='category-insight-missing-history']", count: 0
  end

  test "GET insight explains insufficient history and still shows tips" do
    get category_insight_path(@category)

    assert_response :success
    assert_select "[data-testid='category-insight-missing-history']" do
      assert_select "strong", text: "Aún no tenemos suficiente historial"
    end
    assert_includes response.body.squish,
                    "Para calcular un ahorro estimado necesitamos comparar el gasto promedio de tus últimos 3 ciclos financieros completos."
    assert_select "[data-testid='metric-average']", text: /Sin historial suficiente/
    assert_select "[data-testid='metric-savings']", text: /Sin historial suficiente|—/
    assert_select "[data-testid='category-insight-tips'] .ci-tip", text: /Compara tarifas/
  end

  test "GET insight links to expenses filtered by category" do
    get category_insight_path(@category)

    assert_response :success
    assert_select "a[href='#{expenses_path(category_id: @category.id)}']",
                  text: /Ver gastos de esta categoría/
  end

  test "GET index lists eligible categories" do
    high = Category.create!(name: "High", is_default: true, category_type: "expense",
                            suggested_savings_percentage: 15, savings_potential: "high")
    low = Category.create!(name: "Low", is_default: true, category_type: "expense",
                           suggested_savings_percentage: 5, savings_potential: "low")
    expense_for(high, amount: -300_000, date: Date.current.prev_month)
    expense_for(low, amount: -100_000, date: Date.current.prev_month)

    get category_insights_path
    assert_response :success
    assert_match "High", response.body
    assert_match "Low", response.body
  end

  test "GET index empty state" do
    get category_insights_path
    assert_response :success
  end

  private

  def eligible_categories
    Category.for_user(@user).expenses.active.select do |category|
      category.suggested_savings_percentage.to_d.positive?
    end
  end

  def expense_for(category, amount:, date: Date.current)
    source = @user.money_sources.create!(name: "Bank #{SecureRandom.hex(4)}", kind: "account", active: true,
                                         starting_balance: 1_000_000_000)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount, date: date,
                    description: "x")
  end
end

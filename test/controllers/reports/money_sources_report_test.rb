# frozen_string_literal: true

require "test_helper"

# Redesigned "Origen del gasto" report: summary indicators, source-type
# distribution, hierarchical detail, type filters and the existing drill-down
# to the transactions list of each individual source.
class ReportsMoneySourcesReportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Money Sources UI", email: "reports_money_sources_ui@example.com",
                         password: "password123")
    @category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @account = @user.money_sources.create!(name: "Cuenta de Ahorros", kind: "account", active: true,
                                           starting_balance: 10_000_000)
    @card = @user.money_sources.create!(name: "Tarjeta Visa Infinite", kind: "credit_card", active: true)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true,
                                         starting_balance: 1_000_000)
    sign_in @user
  end

  test "renders the redesigned report with indicators, distribution and hierarchical detail" do
    create_mixed_expenses

    get report_path

    assert_response :success
    assert_select "h1", text: "Origen del gasto"
    assert_select ".reports-subtitle", text: "De dónde sale tu dinero"
    assert_select "#report-period-select"
    assert_select "[data-testid=money-sources-report]"

    assert_select "[data-testid=money-sources-summary] .report-kpi", count: 4
    assert_select "[data-testid=money-source-total]", text: "$1.600.000"
    assert_select "[data-testid=money-source-main]", text: /62,5%/
    assert_select "[data-testid=money-source-main-note]", text: /Cuentas.*1\.000\.000/
    assert_select "[data-testid=money-source-count]", text: "3"
    assert_select "[data-testid=money-source-transactions]", text: "3"

    assert_select "[data-testid=money-source-distribution]"
    assert_select "[data-money-source-donut]"
    assert_select ".money-sources-legend-row", count: 3
    assert_select "[data-testid=money-source-detail]"
    assert_select "tr[data-money-source-group]", count: 3
    assert_select "tr[data-money-source-row]", count: 3
    assert_select "tr.money-sources-total-row", count: 1
  end

  test "the source-type filter scopes every indicator and the detail table" do
    create_mixed_expenses

    get report_path(source_kind: "credit_cards")

    assert_response :success
    assert_select "select[name=source_kind] option[selected][value=credit_cards]"
    assert_select "input[type=hidden][name=source_kind][value=credit_cards]"
    assert_select "[data-testid=money-source-total]", text: "$500.000"
    assert_select "[data-testid=money-source-main]", text: /100/
    assert_select "[data-testid=money-source-count]", text: "1"
    assert_select "[data-testid=money-source-transactions]", text: "1"
    assert_select "tr[data-money-source-group]", count: 1
    assert_select "tr[data-money-source-group][data-money-source-group-key=credit_cards]"
    assert_select "tr[data-money-source-row]", count: 1
    assert_select "tr[data-money-source-row]", text: /Tarjeta Visa Infinite/
  end

  test "individual source rows keep the transactions drill-down with period and source" do
    create_mixed_expenses

    get report_path

    assert_response :success
    links = css_select("tr[data-money-source-row] a.money-sources-source-link")
    card_link = links.find { |link| link.text.include?(@card.name) }
    assert card_link, "credit card source link missing"

    href = card_link["href"]
    assert_includes href, "/reports/transactions"
    assert_includes href, "money_source_id=#{@card.id}"
    assert_includes href, "period=custom"
    assert_includes href, "start_date=2026-10-01"
    assert_includes href, "end_date=2026-10-31"

    assert_select "tr[data-money-source-group] a[href*='/reports/transactions']", count: 0
    assert_select "tr[data-money-source-group] [data-money-source-toggle]", count: 3
  end

  test "clearing filters keeps the selected financial cycle" do
    create_mixed_expenses

    get report_path(source_kind: "accounts")

    assert_response :success
    clear = css_select("[data-testid=money-source-filters] a").first
    assert clear, "clear filters link missing"
    assert_includes clear["href"], "period=custom"
    assert_includes clear["href"], "start_date=2026-10-01"
    assert_includes clear["href"], "end_date=2026-10-31"
    assert_not_includes clear["href"], "source_kind"
  end

  test "shows a friendly empty state for a cycle without expenses" do
    get report_path

    assert_response :success
    assert_select "[data-testid=money-source-empty]"
    assert_select "[data-testid=money-sources-summary]", count: 0
    assert_select "[data-testid=money-source-distribution]", count: 0
  end

  test "distinguishes filters without results from an empty cycle" do
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 10, 5), category: @category,
                           money_source: @account, description: "market")

    get report_path(source_kind: "cash")

    assert_response :success
    assert_select "[data-testid=money-source-empty-filtered]"
    assert_select "[data-testid=money-source-empty]", count: 0
  end

  test "renders an error state when the report cannot be calculated" do
    original = Reports::MoneySources
    failing = Class.new(original) do
      def call
        raise ActiveRecord::StatementInvalid, "boom"
      end
    end

    Reports.send(:remove_const, :MoneySources)
    Reports.const_set(:MoneySources, failing)

    get report_path

    assert_response :service_unavailable
    assert_select "[data-testid=money-source-error]"
  ensure
    Reports.send(:remove_const, :MoneySources)
    Reports.const_set(:MoneySources, original)
  end

  test "keeps report interactions in the dedicated javascript module" do
    create_mixed_expenses

    get report_path

    assert_response :success
    authored_scripts = Nokogiri::HTML(response.body)
                                .css("[data-testid=money-sources-report] script")
                                .reject { |script| script["nonce"].present? }
    assert_empty authored_scripts, "report interactions must live in a dedicated JS file"
    scripts = Nokogiri::HTML(response.body).css("script[src]").map { |script| script["src"] }
    assert scripts.any? { |src| src.include?("reports_money_sources") }
  end

  private

  def create_mixed_expenses
    @user.expenses.create!(amount: -1_000_000, date: Date.new(2026, 10, 5), category: @category,
                           money_source: @account, description: "market")
    @user.expenses.create!(amount: -500_000, date: Date.new(2026, 10, 8), category: @category,
                           money_source: @card, description: "card purchase")
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 10, 12), category: @category,
                           money_source: @cash, description: "cash")
  end

  def report_path(**overrides)
    reports_money_sources_path(
      { period: "custom", start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31) }.merge(overrides)
    )
  end
end

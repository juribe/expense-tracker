# frozen_string_literal: true

require "application_system_test_case"

# Clicking a spending-trend bar must open the transactions report scoped to
# that bucket, the same drill-down the category report offers.
class SpendingTrendDrillDownTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(name: "Trend UI", email: "spending_trend_ui@example.com", password: "password123")
    @user.confirm
    @category = Category.create!(user: @user, name: "Café", category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true, starting_balance: 1_000_000)
    @user.expenses.create!(amount: -100_000, date: Date.new(2026, 9, 3), category: @category,
                           money_source: @bank, description: "Café del día")
    @user.expenses.create!(amount: -200_000, date: Date.new(2026, 9, 3), category: @category,
                           money_source: @bank, description: "Taxi")
  end

  test "clicking a trend bar opens that bucket's transactions" do
    sign_in @user
    visit reports_trends_path(period: "custom", start_date: "2026-09-01", end_date: "2026-09-30")

    assert_selector "[data-spending-trend]"
    wait_for_trend_chart

    assert_equal "function", page.evaluate_script(<<~JS)
      (() => {
        const chart = Chartkick.charts["spending-trend-chart"].getChartObject();
        const callbacks = chart.config._config.options.plugins.tooltip.callbacks;
        return typeof callbacks.label;
      })()
    JS

    tooltip = page.evaluate_script(<<~JS)
      (() => {
        const chart = Chartkick.charts["spending-trend-chart"].getChartObject();
        const callbacks = chart.config._config.options.plugins.tooltip.callbacks;
        return callbacks.label({ dataIndex: 2, formattedValue: "$100.000" });
      })()
    JS
    assert_equal [ "Total gastado: $300.000", "2 transacciones" ], tooltip

    click_trend_bar(2)

    assert_selector "[data-testid=report-transactions-modal].show"
    assert_selector "[data-testid=reports-transactions-table]"
    assert_text "Café del día"
    assert_equal reports_trends_path, page.current_path

    find("button[data-sort-key='amount']").click
    assert_selector "th[aria-sort='ascending'] button[data-sort-key='amount']"
    assert_equal [ "Café del día", "Taxi" ], transaction_descriptions

    find("button[data-sort-key='amount']").click
    assert_selector "th[aria-sort='descending'] button[data-sort-key='amount']"
    assert_equal [ "Taxi", "Café del día" ], transaction_descriptions
    assert_equal reports_trends_path, page.current_path

    page.execute_script(
      "bootstrap.Modal.getOrCreateInstance(document.getElementById('reportTransactionsModal')).hide()"
    )
    wait_for_modal_closed

    visit reports_trends_path(period: "custom", start_date: "2026-09-01",
                              end_date: "2026-09-30", granularity: "week")
    wait_for_trend_chart
    click_trend_bar(0)
    assert_selector "[data-testid=report-transactions-modal].show"
    assert_text "Café del día"

    visit reports_trends_path(period: "custom", start_date: "2026-09-01",
                              end_date: "2026-09-30", granularity: "month")
    wait_for_trend_chart
    click_trend_bar(0)
    assert_selector "[data-testid=report-transactions-modal].show"
    assert_text "Café del día"
  end

  private

  def wait_for_trend_chart
    page.document.synchronize do
      ready = page.evaluate_script(<<~JS)
        (() => {
          const chartkick = window.Chartkick && Chartkick.charts["spending-trend-chart"];
          const chart = chartkick && chartkick.getChartObject();
          return !!(chart && chart.getDatasetMeta(0) && chart.getDatasetMeta(0).data.length > 0);
        })()
      JS
      raise Capybara::ElementNotFound, "trend chart not ready" unless ready
    end
  end

  def click_trend_bar(index)
    page.execute_script(<<~JS)
      (() => {
        const chart = Chartkick.charts["spending-trend-chart"].getChartObject();
        const bar = chart.getDatasetMeta(0).data[#{index}];
        const point = bar.getCenterPoint();
        const rect = chart.canvas.getBoundingClientRect();
        chart.canvas.dispatchEvent(new MouseEvent("click", {
          clientX: rect.left + point.x,
          clientY: rect.top + point.y,
          bubbles: true
        }));
      })()
    JS
  end

  def wait_for_modal_closed
    page.document.synchronize do
      closed = page.evaluate_script(<<~JS)
        (() => {
          const modal = document.getElementById("reportTransactionsModal");
          return !modal || (!modal.classList.contains("show") && !document.querySelector(".modal-backdrop"));
        })()
      JS
      raise Capybara::ElementNotFound, "modal still open" unless closed
    end
  end

  def transaction_descriptions
    page.evaluate_script(
      "Array.from(document.querySelectorAll('[data-testid=reports-transactions-table] tbody tr td:nth-child(2)'))" \
      ".map(function (cell) { return cell.textContent.trim(); })"
    )
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "Correo electrónico", with: user.email, match: :first
    fill_in "Contraseña", with: "password123", match: :first
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

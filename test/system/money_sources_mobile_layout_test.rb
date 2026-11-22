# frozen_string_literal: true

require "application_system_test_case"

# En móvil las tarjetas de fuentes de dinero y el resumen de deuda deben caber
# dentro del viewport de 360 px, sin scroll horizontal ni cifras partidas.
class MoneySourcesMobileLayoutTest < ApplicationSystemTestCase
  MOBILE_WIDTH = 360
  MOBILE_HEIGHT = 800

  setup do
    # Chrome's minimum window width is wider than a phone; emulate the mobile
    # viewport so the assertions run at the requested 360 px.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: MOBILE_WIDTH, height: MOBILE_HEIGHT,
                                    deviceScaleFactor: 1, mobile: true)

    @user = User.create!(name: "Fuentes Móvil",
                         email: "fuentes-movil-#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    @user.confirm

    @account = @user.money_sources.create!(name: "Cuenta Ahorros Banco de Bogotá Principal",
                                           kind: "account", starting_balance: 9_184_000)
    recognition = @account.create_recognition!
    [ "0109", "bancodebogota", "bog", "banco de bogota" ].each do |keyword|
      recognition.recognition_identifiers.create!(kind: "keyword", value: keyword)
    end

    @credit_card = @user.money_sources.create!(name: "Tarjeta de Crédito Visa Signature Davivienda",
                                               kind: "credit_card", starting_balance: -100_500)
    @credit_card.create_credit_account!(credit_limit: 20_200_000, card_brand: "visa",
                                        card_last_four: "5194", statement_day: 15, payment_due_day: 30)

    @loan = @user.money_sources.create!(name: "Crédito Hipotecario Vivienda Principal Banco",
                                        kind: "loan", starting_balance: 0)
    @loan.create_credit_account!(principal_amount: 114_000_000, outstanding_balance: 98_000_000,
                                 installment_amount: 1_800_000, installment_count: 72,
                                 start_date: Date.new(2025, 1, 1))

    sign_in @user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # El driver puede haberse reiniciado si el test falló antes de montar la página.
  end

  test "keeps money source cards inside a 360 px viewport" do
    [ money_sources_cash_path, money_sources_credit_cards_path, money_sources_loans_path ].each do |path|
      visit path

      layout = page.evaluate_script(<<~JS)
        (() => {
          const viewport = document.documentElement.clientWidth;
          const grid = document.querySelector(".loans-grid");
          const cards = Array.from(grid.querySelectorAll("article"));
          return {
            gridOverflows: grid.scrollWidth > grid.clientWidth + 1,
            overflowingCards: cards.filter((card) => {
              const rect = card.getBoundingClientRect();
              return rect.left < -1 || rect.right > viewport + 1;
            }).length
          };
        })()
      JS

      assert_equal 0, layout["overflowingCards"],
                   "las tarjetas deben quedar dentro del viewport en #{path}"
      refute layout["gridOverflows"],
             "la cuadrícula no debe exigir scroll horizontal en #{path}"
    end
  end

  test "keeps debt summary figures readable inside a 360 px viewport" do
    [ [ @credit_card, "la tarjeta de crédito" ], [ @loan, "el préstamo" ] ].each do |source, label|
      visit money_source_path(source, tab: "resumen")

      layout = page.evaluate_script(<<~JS)
        (() => {
          const viewport = document.documentElement.clientWidth;
          const metrics = document.querySelector(".debt-panel-metrics");
          const values = Array.from(metrics.querySelectorAll(".debt-panel-metric-value"));
          const lineCounts = values.map((value) => {
            const range = document.createRange();
            range.selectNodeContents(value);
            const tops = Array.from(range.getClientRects()).map((rect) => Math.round(rect.top));
            return new Set(tops).size;
          });
          const rect = metrics.getBoundingClientRect();
          const borderedMetrics = Array.from(metrics.children).filter((metric) => {
            const style = getComputedStyle(metric);
            return parseFloat(style.borderTopWidth) > 0 ||
                   parseFloat(style.borderBottomWidth) > 0 ||
                   parseFloat(style.borderLeftWidth) > 0 ||
                   parseFloat(style.borderRightWidth) > 0;
          }).length;
          return {
            lineCounts,
            borderedMetrics,
            metricsOverflow: metrics.scrollWidth > metrics.clientWidth + 1,
            metricsOutsideViewport: rect.left < -1 || rect.right > viewport + 1
          };
        })()
      JS

      assert layout["lineCounts"].all? { |count| count == 1 },
             "las cifras del resumen de #{label} deben caber en una línea: #{layout["lineCounts"].inspect}"
      refute layout["metricsOverflow"],
             "las métricas del resumen de #{label} no deben desbordarse"
      refute layout["metricsOutsideViewport"],
             "las métricas del resumen de #{label} deben quedar dentro del viewport"
      assert_equal 0, layout["borderedMetrics"],
                   "las métricas apiladas de #{label} no deben mostrar bordes en móvil"
    end
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

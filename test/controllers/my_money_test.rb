# frozen_string_literal: true

require "test_helper"

class MyMoneyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @category = Category.create!(name: "Mi dinero gasto", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Mi dinero ingreso", is_default: true, category_type: "income")
  end

  test "simple navigation shows Mi dinero and hides Money Sources" do
    user = simple_user
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "a", text: "Mi dinero"
    assert_select "a", text: "Efectivo y Cuentas", count: 0
    assert_select "a", text: "Tarjetas de Crédito", count: 0
    assert_select "a", text: "Transferencias", count: 0
  end

  test "advanced navigation hides Mi dinero" do
    user = detailed_user
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "a", text: "Mi dinero", count: 0
    assert_select "a", text: "Efectivo y Cuentas"
  end

  test "Mi dinero resolves General from the current user" do
    user = simple_user
    general = user.general_money_source
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "h1", text: "Mi dinero"
    assert_select "body", text: /Saldo registrado/
    assert_select "a[href=?]", edit_money_source_path(general), count: 0
    assert_select "body", text: /Money Source|Money Sources/, count: 0
  end

  test "Mi dinero ignores an arbitrary money_source_id parameter" do
    user = simple_user
    general = user.general_money_source
    other = user.money_sources.create!(name: "Otra fuente", kind: "account", starting_balance: 1_000_000)
    sign_in user

    get my_money_path(money_source_id: other.id)

    assert_response :success
    assert_equal general.id, controller.instance_variable_get(:@money_source).id
    assert_select "body", text: /Otra fuente/, count: 0
  end

  test "General is created once and reused across visits" do
    user = simple_user
    general = user.general_money_source
    general.destroy!
    sign_in user

    assert_difference "MoneySource.where(general: true).count", 1 do
      get my_money_path
    end
    created = user.reload.general_money_source

    assert_no_difference "MoneySource.where(general: true).count" do
      get my_money_path
      get my_money_path
    end
    assert_equal created.id, user.reload.general_money_source.id
  end

  test "detailed users cannot open the simple Mi dinero entry point" do
    user = detailed_user
    sign_in user

    get my_money_path

    assert_redirected_to dashboard_path
  end

  test "simple users cannot open the technical Money Source detail" do
    user = simple_user
    general = user.general_money_source
    sign_in user

    get money_source_path(general)

    assert_redirected_to dashboard_path
  end

  test "simple users cannot open another historical source by URL" do
    user = simple_user
    other = user.money_sources.create!(name: "Histórica", kind: "account", starting_balance: 1_000_000)
    sign_in user

    get money_source_path(other)
    assert_redirected_to dashboard_path

    get extractos_money_source_path(other)
    assert_redirected_to dashboard_path
  end

  test "simple users cannot edit or change General through direct requests" do
    user = simple_user
    general = user.general_money_source
    sign_in user

    patch money_source_path(general), params: {
      money_source: { kind: "account", name: "Cuenta hackeada", identifier: "1234" }
    }

    assert_redirected_to dashboard_path
    general.reload
    assert_equal "general", general.kind
    assert_equal "General", general.name
    assert_nil general.identifier
  end

  test "advanced financial routes stay blocked for simple General" do
    user = simple_user
    general = user.general_money_source
    other = user.money_sources.create!(name: "Otra", kind: "account", starting_balance: 0)
    sign_in user

    post transfers_path, params: {
      transfer: { from_source_id: general.id, to_source_id: other.id, amount: "1000", date: Date.current.to_s }
    }
    assert_redirected_to dashboard_path

    get reconciliation_path
    assert_redirected_to dashboard_path

    get reports_money_sources_path
    assert_redirected_to dashboard_path
  end

  test "advanced users keep the current Money Source detail and actions" do
    user = detailed_user
    general = user.general_money_source
    sign_in user

    get money_source_path(general)

    assert_response :success
    assert_select "a[href=?]", edit_money_source_path(general)
    assert_select "body", text: /Saldo actual|Saldo/
  end

  test "Mi dinero shows the recorded balance and a neutral negative message" do
    user = simple_user
    general = user.general_money_source
    user.expenses.create!(amount: 30_000, date: Date.current, description: "Almuerzo",
                          category: @category, source: "manual")
    sign_in user

    assert_equal BigDecimal("-30000"), general.reload.balance

    get my_money_path

    assert_response :success
    assert_select "body", text: /Saldo registrado/
    assert_select "body", text: /Los gastos registrados superan los ingresos registrados/
    assert_select "body", text: /pendiente de conciliación|sobregiro|deuda bancaria/i, count: 0
  end

  test "Mi dinero shows only General expenses and incomes" do
    user = simple_user
    general = user.general_money_source
    user.expenses.create!(amount: 20_000, date: Date.current, description: "Almuerzo Mi dinero",
                          category: @category, source: "manual")
    user.incomes.create!(amount: 50_000, date: Date.current, description: "Ingreso Mi dinero",
                         category: @income_category, source: "manual")
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "body", text: /Almuerzo Mi dinero/
    assert_select "body", text: /Ingreso Mi dinero/
    assert_select "th", text: "Fuente", count: 0
    assert_select "td", text: "General", count: 0
    assert_equal general.id, user.expenses.order(:created_at).last.money_source_id
    assert_equal general.id, user.incomes.order(:created_at).last.money_source_id
  end

  test "Mi dinero includes transactions from historical sources after switching to simple" do
    user = detailed_user
    historical = user.money_sources.create!(name: "Cuenta histórica", kind: "account", starting_balance: 100_000)
    user.expenses.create!(amount: 25_000, date: Date.current, description: "Gasto histórico",
                          category: @category, source: "manual", money_source: historical)
    user.incomes.create!(amount: 80_000, date: Date.current, description: "Ingreso histórico",
                         category: @income_category, source: "manual", money_source: historical)
    MoneySources::ModeSwitch.new(user: user, mode: "simple").call
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "body", text: /Gasto histórico/
    assert_select "body", text: /Ingreso histórico/
    assert_select "body", text: /Cuenta histórica/, count: 0
    assert_select ".stat-value", text: /55[.,]000/
  end

  test "Mi dinero keeps an opening balance from historical movements" do
    user = detailed_user
    historical = user.money_sources.create!(name: "Cuenta saldo previo", kind: "account")
    user.incomes.create!(amount: 100_000, date: Date.current - 40.days, description: "Ingreso previo",
                         category: @income_category, source: "manual", money_source: historical)
    user.expenses.create!(amount: 40_000, date: Date.current, description: "Gasto actual",
                          category: @category, source: "ai", money_source: historical)
    MoneySources::ModeSwitch.new(user: user, mode: "simple").call
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "body", text: /100[.,]000/
    assert_select "body", text: /60[.,]000/
    assert_select ".stat-value", text: /60[.,]000/
    assert_select "[data-testid=my-money-period-balance]", text: /40[.,]000/
    assert_select "[data-testid=my-money-period-balance]", text: /60[.,]000/, count: 0
  end

  test "Mi dinero points to Gastos when the period has no movements" do
    user = detailed_user
    historical = user.money_sources.create!(name: "Cuenta sin ciclo", kind: "account")
    user.expenses.create!(amount: 10_000, date: Date.current - 60.days, description: "Gasto antiguo",
                          category: @category, source: "ai", money_source: historical)
    MoneySources::ModeSwitch.new(user: user, mode: "simple").call
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "body", text: /No hay movimientos en este período/
    assert_select "a[href=?]", expenses_path, text: /Ver historial en Gastos/
  end

  test "Mi dinero keeps the statement filters and labels" do
    user = simple_user
    general = user.general_money_source
    user.expenses.create!(amount: 20_000, date: Date.current, description: "Gasto filtro",
                          category: @category, source: "manual")
    user.incomes.create!(amount: 50_000, date: Date.current, description: "Ingreso filtro",
                         category: @income_category, source: "manual")
    sign_in user

    get extractos_money_source_path(general, kind: "in")

    assert_response :success
    assert_select "body", text: /Ingreso filtro/
    assert_select "body", text: /Gasto filtro/, count: 0
    assert_select "body", text: /Ingresos/
    assert_select "body", text: /Gastos/
    assert_select "body", text: /Entradas|Salidas/, count: 0
  end

  test "Mi dinero keeps pagination" do
    user = simple_user
    general = user.general_money_source
    26.times do |index|
      user.expenses.create!(amount: index + 1, date: Date.current, description: "Movimiento #{index}",
                            category: @category, source: "manual")
    end
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "a.page-link", text: "2"
    assert_equal 25, controller.instance_variable_get(:@statement).movements.size
  end

  test "Mi dinero hides advanced actions and technical configuration" do
    user = simple_user
    user.general_money_source
    sign_in user

    get my_money_path

    assert_response :success
    assert_select "a", text: /Transferir|Depositar|Retirar|Conciliar|Editar/, count: 0
    assert_select "body", text: /Entidad financiera|Identificador|Número de cuenta|Últimos cuatro|Fecha de corte|Fecha de pago|Exenta 4x1.000/, count: 0
    assert_select "[data-testid=negative-balance-warning]", count: 0
  end

  private

  def simple_user
    User.create!(name: "My Money Simple", email: "my_money_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end

  def detailed_user
    User.create!(name: "My Money Advanced", email: "my_money_advanced_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end

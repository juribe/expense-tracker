# frozen_string_literal: true

require "test_helper"

class PageTitlesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Test User", email: "page_titles@example.com", password: "password123")
    @user.confirm
    @category = Category.create!(name: "Food", is_default: true, category_type: "expense")
    @source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000_000)
  end

  test "GET dashboard resolves the I18n title" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_equal "Resumen financiero", @controller.instance_variable_get(:@page_title)
    assert_select "title", "Resumen financiero | #{AppName.current}"
  end

  test "GET expenses index resolves the I18n title" do
    sign_in @user
    get expenses_path
    assert_response :success
    assert_equal "Gastos", @controller.instance_variable_get(:@page_title)
    assert_select "title", "Gastos | #{AppName.current}"
  end

  test "GET reports overview resolves the I18n title" do
    sign_in @user
    get reports_overview_path
    assert_response :success
    assert_select "title", "Reportes financieros | #{AppName.current}"
  end

  test "GET money sources index resolves the I18n title" do
    sign_in @user
    get money_sources_cash_path
    assert_response :success
    assert_select "title", "Fuentes de dinero | #{AppName.current}"
  end

  test "titles and the footer use APP_NAME for branding" do
    sign_in @user
    with_env("APP_NAME" => "Mis Gastos") do
      get dashboard_path
    end

    assert_response :success
    assert_select "title", "Resumen financiero | Mis Gastos"
    assert_select "footer", text: /© #{Date.current.year} Mis Gastos/
  end

  test "missing translation does not raise and leaves the title nil" do
    controller = ApplicationController.new
    controller.define_singleton_method(:controller_name) { "unknown" }
    controller.define_singleton_method(:action_name) { "missing" }

    assert_nil controller.set_page_title
    assert_nil controller.instance_variable_get(:@page_title)
  end

  test "non-GET requests do not execute the title callback" do
    sign_in @user
    post expenses_path, params: {
      expense: {
        amount: 10,
        date: Date.current,
        category_id: @category.id,
        money_source_id: @source.id,
        description: "x"
      }
    }

    assert_includes [ 200, 302, 303 ], response.status
    assert_nil @controller.instance_variable_get(:@page_title)
  end

  test "private pages use noindex, nofollow" do
    sign_in @user
    get dashboard_path
    assert_select 'meta[name="robots"][content="noindex, nofollow"]'
  end
end

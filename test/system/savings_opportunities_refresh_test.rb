# frozen_string_literal: true

require "application_system_test_case"

# The refresh button must show progress without a manual reload and must stop
# polling as soon as the background analysis publishes its state.
class SavingsOpportunitiesRefreshTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @setting = PaymentEngine::Setting.current
    @setting.update!(paid_access_required: true)
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Savings Opportunities UI",
      code: "SAVINGS_OPPS_UI_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(name: "Savings UI", email: "savings_ops_ui@example.com", password: "password123")
    @user.confirm
    @category = Category.create!(user: @user, name: "Comidas UI", is_default: false, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    Expense.create!(user: @user, category: @category, money_source: @bank, amount: -50_000,
                    date: Date.current.beginning_of_month, description: "Restaurante")
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: 1.month.from_now
    )

    @previous_cache = SavingsOpportunities::AnalysisState.cache
    SavingsOpportunities::AnalysisState.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    SavingsOpportunities::AnalysisState.cache = @previous_cache
  end

  test "shows progress immediately and stops when the analysis is ready" do
    with_env("MISTRAL_API_KEY" => "test-key") do
      sign_in @user
      visit savings_opportunities_path

      click_button "Actualizar análisis"

      assert_text "Generando el análisis inteligente…"
      assert_button "Actualizando…", disabled: true

      SavingsOpportunities::AnalysisState.write(@user.id, "ready")

      assert_button "Actualizar análisis", wait: 10
      refute_text "Generando el análisis inteligente…"
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

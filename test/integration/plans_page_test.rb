# frozen_string_literal: true

require "test_helper"

class PlansPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @setting = PaymentEngine::Setting.current
    @setting.update!(
      paid_access_required: true,
      free_trial_enabled: true,
      free_trial_duration_days: 30
    )

    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "PLANS_PAGE") do |type|
      type.name = "Plans Page"
      type.status = "active"
    end

    @monthly = PaymentEngine::PaymentOption.find_or_initialize_by(name: "Mensual")
    @monthly.update!(
      membership_type: @membership_type,
      price: 14_900,
      currency: "COP",
      mode: "recurring",
      interval: "month",
      interval_count: 1,
      trial_days: 0,
      status: "active",
      position: 1,
      access_duration_count: 1,
      access_duration_unit: "month"
    )

    @annual = PaymentEngine::PaymentOption.find_or_initialize_by(name: "Anual")
    @annual.update!(
      membership_type: @membership_type,
      price: 149_900,
      currency: "COP",
      mode: "one_time",
      interval: nil,
      interval_count: nil,
      trial_days: 0,
      status: "active",
      position: 2,
      access_duration_count: 12,
      access_duration_unit: "month"
    )

    @user = User.create!(
      name: "Plans Page User",
      email: "plans-page-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "renders the three plans with real prices and the configured trial days" do
    get plans_path

    assert_response :success
    assert_select "article.plans-card--free", count: 1
    assert_includes response.body, "Gratis"
    assert_includes response.body, "Pro mensual"
    assert_includes response.body, "Pro anual"
    assert_includes response.body, "30 días"
    assert_includes response.body, "FUNCIONES PRO INCLUIDAS POR 30 DÍAS"
    refute_includes response.body, "FUNCIONES PRO NO INCLUIDAS"
    assert_includes response.body, "14.900"
    assert_includes response.body, "149.900"
    assert_includes response.body, "Ahorras $28.900 al año"
  end

  test "lists the Pro features included with both paid plans" do
    get plans_path

    assert_response :success
    assert_includes response.body, "Chat financiero con IA"
    assert_includes response.body, "Análisis de gastos y oportunidades de ahorro"
    assert_includes response.body, "Registra gastos automáticamente al recibir correos de tus bancos"
    assert_includes response.body, "Crea gastos por WhatsApp"
    assert_includes response.body, "Herramientas avanzadas de planificación financiera"
  end

  test "hides the free plan after the user has used it" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "expired",
      source: "trial",
      starts_at: 2.months.ago,
      expires_at: 1.day.ago
    )

    get plans_path

    assert_response :success
    assert_select "article.plans-card--free", count: 0
    assert_includes response.body, "¿Qué pasa cuando termina mi prueba Pro?"
    assert_includes response.body, "no pierdes tu cuenta ni tus datos"
  end

  test "hides the free plan for a paid member" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.week.ago,
      expires_at: 1.month.from_now
    )

    get plans_path

    assert_response :success
    assert_select "article.plans-card--free", count: 0
  end

  test "does not offer free access before the user has a membership" do
    get plans_path

    assert_response :success
    assert_no_match(/Continuar con el plan gratis/, response.body)
    assert_includes response.body, "Disponible cuando termine tu prueba"
  end

  test "highlights an active trial instead of offering a new one" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "trial",
      starts_at: 2.days.ago,
      expires_at: 28.days.from_now
    )

    get plans_path

    assert_response :success
    assert_select "article.plans-card--free", count: 0
    assert_includes response.body, "Tu prueba Pro está activa"
    assert_no_match(/Comenzar prueba gratis/, response.body)
  end

  test "hides the trial banner when free trials are disabled" do
    @setting.update!(free_trial_enabled: false)

    get plans_path

    assert_response :success
    assert_no_match(/Disfruta de Yogasto Pro gratis/, response.body)
    assert_no_match(/Comenzar prueba gratis/, response.body)
  end
end

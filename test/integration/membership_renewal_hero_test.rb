# frozen_string_literal: true

require "test_helper"

# The dashboard renewal hero appears only when the user has had a membership
# and currently has no PRO access. It promotes renewal without gating the free
# dashboard or duplicating the membership access rules.
class MembershipRenewalHeroTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @setting = PaymentEngine::Setting.current
    @setting.update!(paid_access_required: true)
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Renewal Hero",
      code: "RENEWAL_HERO_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Renewal Hero User",
      email: "renewal-hero-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "shows the renewal hero after a paid membership expires" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='membership-renewal-hero']" do
      assert_select "h2", text: "Recupera el acceso a todas las funciones de Yogasto"
      assert_select "a[href='#{plans_path}']", text: /Renovar membresía/
      assert_select "[data-testid='membership-benefits-button']", text: "Ver beneficios"
    end
    assert_select "a.metric-card", count: 8
  end

  test "shows the renewal hero after the free trial ends" do
    create_membership(source: "trial", expires_at: 1.day.ago)

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='membership-renewal-hero']"
  end

  test "does not show the renewal hero with an active paid membership" do
    create_membership(source: "purchase", expires_at: 1.month.from_now)

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='membership-renewal-hero']", count: 0
  end

  test "does not show the renewal hero during an active trial" do
    create_membership(source: "trial", expires_at: 10.days.from_now)

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='membership-renewal-hero']", count: 0
  end

  test "does not show the renewal hero to a free user who never had a membership" do
    @setting.update!(paid_access_required: false)

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='membership-renewal-hero']", count: 0
    assert_select "a.metric-card", count: 8
  end

  test "the benefits modal lists the recovered PRO capabilities" do
    create_membership(source: "purchase", expires_at: 1.day.ago)

    get dashboard_path

    assert_response :success
    assert_select "#membershipBenefitsModal" do
      assert_includes response.body, "Todo lo que recuperas con PRO"
      assert_includes response.body, "Automatizaciones"
      assert_includes response.body, "Email, Gmail y WhatsApp"
      assert_includes response.body, "Inteligencia artificial"
      assert_includes response.body, "Reglas"
      assert_includes response.body, "Integraciones"
      assert_includes response.body, "Análisis"
      assert_includes response.body, "Candidatos y procesamiento"
      assert_select "a[href='#{plans_path}']", text: /Renovar membresía/
    end
  end

  private

  def create_membership(source:, expires_at:)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: source,
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end
end

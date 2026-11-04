# frozen_string_literal: true

require "test_helper"

class MembershipAccessGatingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @setting = PaymentEngine::Setting.current
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Gating Test",
      code: "GATING_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Gating User",
      email: "gating_#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "redirects to plans when paid access is required and the user has no membership" do
    @setting.update!(paid_access_required: true)
    sign_in @user

    get dashboard_path

    assert_redirected_to plans_path
    assert_equal "Selecciona una membresía para continuar.", flash[:alert]
  end

  test "allows access with an active membership" do
    @setting.update!(paid_access_required: true)
    create_membership(expires_at: 1.month.from_now)
    sign_in @user

    get dashboard_path

    assert_response :success
  end

  test "allows access when the membership has expired" do
    @setting.update!(paid_access_required: true)
    create_membership(expires_at: 1.day.ago)
    sign_in @user

    get dashboard_path

    assert_response :success
  end

  test "allows access when paid access is not required" do
    @setting.update!(paid_access_required: false)
    sign_in @user

    get dashboard_path

    assert_response :success
  end

  test "plans page shows the selection notice through user access" do
    @setting.update!(paid_access_required: true)
    sign_in @user

    get plans_path

    assert_response :success
    assert_includes response.body, "Elige tu membresía para continuar"
  end

  private

  def create_membership(expires_at:)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end
end

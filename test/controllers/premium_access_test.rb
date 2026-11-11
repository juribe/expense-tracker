# frozen_string_literal: true

require "test_helper"

# Minimal controllers used to verify the shared premium callback without
# assigning premium behavior to a production controller.
class PremiumGateTestController < ApplicationController
  require_premium only: :premium

  def premium
    render plain: "premium"
  end

  def free
    render plain: "free"
  end
end

class PremiumGateExceptTestController < ApplicationController
  require_premium except: :free

  def premium
    render plain: "premium"
  end

  def free
    render plain: "free"
  end
end

class PremiumGateAllTestController < ApplicationController
  require_premium

  def premium
    render plain: "premium"
  end

  def free
    render plain: "free"
  end
end

class PremiumAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  with_routing do |set|
    set.draw do
      get "/dashboard", to: "dashboard#index", as: :dashboard
      get "/plans", to: "plans#index", as: :plans
      get "/premium-gate/premium", to: "premium_gate_test#premium"
      get "/premium-gate/free", to: "premium_gate_test#free"
      get "/premium-gate-except/premium", to: "premium_gate_except_test#premium"
      get "/premium-gate-except/free", to: "premium_gate_except_test#free"
      get "/premium-gate-all/premium", to: "premium_gate_all_test#premium"
      get "/premium-gate-all/free", to: "premium_gate_all_test#free"
    end
  end

  setup do
    @setting = PaymentEngine::Setting.current
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Premium Access Test",
      code: "PREMIUM_ACCESS_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(
      name: "Premium Access User",
      email: "premium-access-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "require_premium renders the premium lock page for non-premium users" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "purchase", status: "expired", expires_at: 1.day.ago)
    sign_in @user

    get "/premium-gate/premium"

    assert_response :success
    assert_select "[data-testid='premium-locked']" do
      assert_select "h1", text: "Esta función es Premium"
      assert_select "a[href=?]", plans_path
      assert_select "a[href=?]", dashboard_path
    end
  end

  test "require_premium allows users with an active trial" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "trial", status: "active", expires_at: 2.days.from_now)
    sign_in @user

    get "/premium-gate/premium"

    assert_response :success
    assert_equal "premium", response.body
  end

  test "require_premium allows users with an active paid membership" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "purchase", status: "active", expires_at: 1.month.from_now)
    sign_in @user

    get "/premium-gate/premium"

    assert_response :success
    assert_equal "premium", response.body
  end

  test "require_premium allows access when paid access is not required" do
    @setting.update!(paid_access_required: false)
    sign_in @user

    get "/premium-gate/premium"

    assert_response :success
    assert_equal "premium", response.body
  end

  test "require_premium protects every action when no options are given" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "purchase", status: "expired", expires_at: 1.day.ago)
    sign_in @user

    get "/premium-gate-all/free"

    assert_response :success
    assert_select "[data-testid='premium-locked']"
  end

  test "require_premium answers JSON requests with a forbidden error" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "purchase", status: "expired", expires_at: 1.day.ago)
    sign_in @user

    get "/premium-gate/premium", as: :json

    assert_response :forbidden
    assert_equal PremiumAccessTestHelper::PREMIUM_ALERT, response.parsed_body["error"]
  end

  test "require_premium supports only" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "purchase", status: "expired", expires_at: 1.day.ago)
    sign_in @user

    get "/premium-gate/free"

    assert_response :success
    assert_equal "free", response.body
  end

  test "require_premium supports except" do
    @setting.update!(paid_access_required: true)
    create_membership(source: "purchase", status: "expired", expires_at: 1.day.ago)
    sign_in @user

    get "/premium-gate-except/free"

    assert_response :success
    assert_equal "free", response.body

    get "/premium-gate-except/premium"

    assert_response :success
    assert_select "[data-testid='premium-locked']"
  end

  private

  def create_membership(source:, status:, expires_at:)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: status,
      source: source,
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end
end

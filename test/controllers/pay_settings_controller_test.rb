# frozen_string_literal: true

require "test_helper"

class PaySettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Pay Settings User",
      email: "pay_settings_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "GET /settings/pay renders the form with calendar default" do
    get pay_settings_path
    assert_response :success
    assert_select "select[name=?]", "user[financial_cycle_start_day]"
  end

  test "PATCH /settings/pay configures the financial cycle start day" do
    patch pay_settings_path, params: { user: { financial_cycle_start_day: "20" } }

    assert_redirected_to pay_settings_path
    assert_equal 20, @user.reload.financial_cycle_start_day
    assert @user.financial_cycles_enabled?
  end

  test "PATCH /settings/pay rejects a start day outside 1..28" do
    patch pay_settings_path, params: { user: { financial_cycle_start_day: "30" } }

    assert_response :unprocessable_entity
    assert_equal 1, @user.reload.financial_cycle_start_day
  end

  test "PATCH /settings/pay can reset to calendar months" do
    @user.update!(financial_cycle_start_day: 20)

    patch pay_settings_path, params: { user: { financial_cycle_start_day: "1" } }

    assert_redirected_to pay_settings_path
    assert_not @user.reload.financial_cycles_enabled?
  end
end

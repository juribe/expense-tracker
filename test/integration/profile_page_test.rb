require "test_helper"

class ProfilePageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "profile-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    sign_in @user
  end

  test "profile page renders" do
    get profile_path
    assert_response :success
    assert_includes response.body, "Mi perfil"
    assert_includes response.body, "Ver planes"
  end

  test "profile page links to account security" do
    get profile_path

    assert_response :success
    assert_select "a[href='#{security_settings_path}']"
  end

  test "profile page links to the data deletion policy" do
    get profile_path

    assert_response :success
    assert_select "a[href='/eliminacion-de-datos']"
  end
end

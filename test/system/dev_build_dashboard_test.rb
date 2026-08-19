require "application_system_test_case"

class DevBuildDashboardTest < ApplicationSystemTestCase
  test "dashboard page loads and shows content" do
    visit "/users/sign_up"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_button "Sign up"
    assert_text "Welcome! You have signed up successfully."
    
    visit "/dashboard"
    assert_current_path "/dashboard"
    assert_selector "h1", text: "Dashboard"
    assert_text "Monthly Summary"
  end
end

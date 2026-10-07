# frozen_string_literal: true

require "test_helper"

class FinancialSummaryControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "financial_summary_page_test@example.com",
      password: "password123"
    )
  end

  test "GET /financial_summary renders for authenticated user" do
    sign_in @user
    get financial_summary_path
    assert_response :success
    assert_select "h1"
  end

  test "GET /financial_summary shows the financial cycle badge in the title with a schedule" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.current(@user)
    sign_in @user

    get financial_summary_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.label}/
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.range_label}/
  end

  test "GET /financial_summary shows no cycle badge without a configured schedule" do
    sign_in @user

    get financial_summary_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", count: 0
    assert_select "h1"
  end

  test "GET /financial_summary redirects unauthenticated user to sign in" do
    get financial_summary_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "sidebar includes financial summary link" do
    sign_in @user
    get dashboard_path
    assert_select "a[href='#{financial_summary_path}']"
  end
end

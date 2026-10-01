# frozen_string_literal: true

require "test_helper"

class FinancialChatControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "financial_chat_test@example.com",
      password: "password123"
    )
  end

  test "GET /financial_chat renders for authenticated user" do
    sign_in @user
    get financial_chat_path
    assert_response :success
    assert_select "h1", text: I18n.t("financial_chat.title")
  end

  test "GET /financial_chat redirects unauthenticated user to sign in" do
    get financial_chat_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "sidebar includes financial chat link" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_select "a[href='#{financial_chat_path}']"
  end
end

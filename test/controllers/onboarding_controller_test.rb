# frozen_string_literal: true

require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Onboarding Ctrl User",
      email: "onboarding_ctrl@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "POST skip requires authentication" do
    sign_out @user

    post onboarding_skip_path(step: "gmail")

    assert_response :redirect
    assert_match(/sign_in/, response.location)
    assert_empty OnboardingProgress.where(user_id: @user.id)
  end

  test "POST skip persists the current step as skipped" do
    post onboarding_skip_path(step: "gmail")

    assert_redirected_to dashboard_path
    assert OnboardingProgress.for_user(@user.reload).skipped?("gmail")
    assert_not OnboardingProgress.for_user(@user).skipped?("initial")
    assert_not OnboardingProgress.for_user(@user).skipped?("whatsapp")
  end

  test "POST skip is idempotent and keeps the other steps pending" do
    post onboarding_skip_path(step: "initial")
    post onboarding_skip_path(step: "initial")

    progress = OnboardingProgress.for_user(@user.reload)
    assert_equal [ "initial" ], progress.skipped_steps
    assert_not progress.skipped?("gmail")
    assert_not progress.skipped?("whatsapp")
  end

  test "POST skip rejects unknown steps without persisting anything" do
    post onboarding_skip_path(step: "wallet")

    assert_redirected_to dashboard_path
    assert_match(/no es válido/i, flash[:alert])
    assert_empty OnboardingProgress.where(user_id: @user.id)
  end

  test "POST skip_all skips every pending step, not the completed ones" do
    @user.gmail_connections.create!(email: "onboarding@gmail.com", active: true)

    post onboarding_skip_all_path

    assert_redirected_to dashboard_path
    progress = OnboardingProgress.for_user(@user.reload)
    assert progress.skipped?("initial")
    assert progress.skipped?("whatsapp")
    assert_not progress.skipped?("gmail")
  end

  test "POST skip_all only affects the signed-in user" do
    other_user = User.create!(
      name: "Other Ctrl User",
      email: "onboarding_ctrl_other@example.com",
      password: "password123"
    )

    post onboarding_skip_all_path

    assert_redirected_to dashboard_path
    assert_not OnboardingProgress.for_user(other_user).skipped?("initial")
    assert_not OnboardingProgress.for_user(other_user).skipped?("gmail")
    assert_not OnboardingProgress.for_user(other_user).skipped?("whatsapp")
  end
end

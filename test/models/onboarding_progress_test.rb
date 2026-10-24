# frozen_string_literal: true

require "test_helper"

class OnboardingProgressTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Onboarding User",
      email: "onboarding_model@example.com",
      password: "password123"
    )
  end

  test "starts with no skipped steps" do
    progress = @user.build_onboarding_progress

    assert_empty progress.skipped_steps
    assert_not progress.skipped?(:initial)
    assert_not progress.skipped?(:gmail)
    assert_not progress.skipped?(:whatsapp)
  end

  test "skip! marks a step as skipped permanently" do
    progress = OnboardingProgress.for_user(@user)
    progress.skip!(:gmail)
    progress.save!

    reloaded = OnboardingProgress.for_user(@user.reload)
    assert reloaded.skipped?("gmail")
  end

  test "skip! is idempotent and keeps the other steps pending" do
    progress = OnboardingProgress.for_user(@user)
    progress.skip!(:initial)
    progress.skip!(:initial)

    assert_equal [ "initial" ], progress.skipped_steps
    assert_not progress.skipped?("gmail")
    assert_not progress.skipped?("whatsapp")
  end

  test "skip! rejects unknown steps" do
    progress = OnboardingProgress.for_user(@user)

    assert_raises(ArgumentError) { progress.skip!(:wallet) }
    assert_empty progress.skipped_steps
  end

  test "skipped? only reports steps that were actually skipped" do
    progress = OnboardingProgress.for_user(@user)
    progress.skip!(:whatsapp)

    assert progress.skipped?("whatsapp")
    assert_not progress.skipped?("initial")
    assert_not progress.skipped?("gmail")
  end

  test "skip_all! marks several steps at once" do
    progress = OnboardingProgress.for_user(@user)
    progress.skip_all!([ "initial", "gmail", "whatsapp" ])

    %w[initial gmail whatsapp].each do |step|
      assert progress.skipped?(step)
    end
  end

  test "skipped steps are independent between users" do
    other_user = User.create!(
      name: "Other User",
      email: "onboarding_other@example.com",
      password: "password123"
    )

    onboarding_progress = OnboardingProgress.for_user(@user)
    onboarding_progress.skip!(:initial)
    onboarding_progress.save!

    assert_not OnboardingProgress.for_user(other_user).skipped?("initial")
    assert_empty OnboardingProgress.for_user(other_user).skipped_steps
    assert_equal [ "initial" ], OnboardingProgress.for_user(@user.reload).skipped_steps
  end

  test "for_user returns a default unpersisted record for a user with no row" do
    progress = OnboardingProgress.for_user(@user)

    assert_not progress.persisted?
    assert_empty progress.skipped_steps
    assert_not @user.onboarding_progress.persisted?
  end

  test "rejects unknown values persisted into skipped_steps" do
    progress = OnboardingProgress.for_user(@user)
    progress.skipped_steps = [ "initial", "wallet" ]

    assert_not progress.valid?
    assert progress.errors[:skipped_steps].present?
  end
end

# frozen_string_literal: true

# PremiumAccessTestHelper
# Minitest shared behavior for controllers that declare `require_premium`.
#
# Include it in an integration test and declare one line per page:
#
#   include PremiumAccessTestHelper
#
#   should_require_premium("financial chat") { get financial_chat_path }
#   should_allow_premium("financial chat") { get financial_chat_path }
#
# `should_require_premium` enables paid access, gives the test user an expired
# membership, performs the request and asserts the premium lock page is
# rendered. `should_allow_premium` grants an active membership and asserts the
# page renders.
module PremiumAccessTestHelper
  PREMIUM_ALERT = "Necesitas un plan premium para utilizar esta función."

  def self.included(base)
    base.include Devise::Test::IntegrationHelpers
    base.extend(ClassMethods)
  end

  module ClassMethods
    def should_require_premium(description, &request)
      test("#{description} requires premium access") do
        PaymentEngine::Setting.current.update!(paid_access_required: true)
        revoke_premium(premium_test_user)
        sign_in premium_test_user
        instance_exec(&request)

        assert_premium_lock_page
      end
    end

    def should_allow_premium(description, &request)
      test("#{description} allows premium users") do
        grant_premium(premium_test_user)
        sign_in premium_test_user
        instance_exec(&request)

        assert_response :success
      end
    end
  end

  # Reuses the class setup user when there is one so premium pages render with
  # the same data as the rest of the suite; otherwise creates a dedicated user.
  def premium_test_user
    @premium_test_user ||= @user || User.create!(
      name: "Premium Access User",
      email: "premium_access_#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  def assert_premium_lock_page
    assert_response :success

    assert_select "[data-testid='premium-locked']" do
      assert_select "h1", text: "Esta función es Premium"
      assert_select "a[href=?]", plans_path
      assert_select "a[href=?]", dashboard_path
    end
  end

  def grant_premium(user)
    replace_membership(user, status: "active", starts_at: 1.month.ago, expires_at: 1.month.from_now)
  end

  def revoke_premium(user)
    replace_membership(user, status: "expired", starts_at: 2.months.ago, expires_at: 1.day.ago)
  end

  private

  def replace_membership(user, status:, starts_at:, expires_at:)
    PaymentEngine::Membership.where(owner: user).delete_all
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: premium_test_membership_type,
      status: status,
      source: "purchase",
      starts_at: starts_at,
      expires_at: expires_at
    )
  end

  def premium_test_membership_type
    @premium_test_membership_type ||= PaymentEngine::MembershipType.create!(
      name: "Premium Access Test",
      code: "PREMIUM_ACCESS_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end
end

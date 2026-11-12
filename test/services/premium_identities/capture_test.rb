# frozen_string_literal: true

require "test_helper"

# PremiumIdentities::Capture records every premium identity a user owns. It is
# called before destroy so legacy memberships do not lose their email history
# when the account is closed.
class PremiumIdentitiesCaptureTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Capture Test",
      code: "CAPTURE_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end

  test "captures the account email and connected channels before destroy" do
    user = create_user("capture")
    create_membership(user)
    GmailConnection.create!(user: user, email: "capture-inbox@gmail.com")
    EmailSource.create!(user: user, source_type: "forwarding", email: "capture-redirect@example.com",
                        status: "active")
    WhatsappIdentity.create!(phone_number: "+57 300 111 2222", claimed_by_user: user,
                             claimed_at: Time.current)

    user.destroy!

    assert_equal %w[account_email gmail redirect_email whatsapp].sort,
                 PremiumIdentity.order(:identity_type).pluck(:identity_type)
    assert PremiumIdentity.all.all? { |identity| identity.first_user_id.nil? }
  end

  test "does not capture identities for a user without membership history" do
    user = create_user("free-capture")
    GmailConnection.create!(user: user, email: "free-capture@gmail.com")

    assert_no_difference -> { PremiumIdentity.count } do
      user.destroy!
    end
  end

  test "a legacy membership with the same email cannot be reused after account deletion" do
    email = "legacy-same-#{SecureRandom.hex(4)}@example.com"
    user = create_user("legacy-same", email: email)
    create_membership(user)
    user.destroy!

    replacement = create_user("legacy-same-replacement", email: email)
    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: replacement)

    assert_not result.success?
    assert_equal 0, PaymentEngine::Membership.where(owner: replacement).count
  end

  test "a legacy membership with a Gmail alias cannot be reused after account deletion" do
    alias_user = create_user("legacy-alias", email: "legacy.alias+first@gmail.com")
    create_membership(alias_user)
    alias_user.destroy!

    replacement = create_user("legacy-alias-replacement", email: "legacyalias@gmail.com")
    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: replacement)

    assert_not result.success?
    assert_equal 0, PaymentEngine::Membership.where(owner: replacement).count
  end

  private

  def create_user(prefix, email: nil)
    User.create!(
      name: prefix.titleize,
      email: email || "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_membership(user)
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.day.ago,
      expires_at: 1.month.from_now
    )
  end
end

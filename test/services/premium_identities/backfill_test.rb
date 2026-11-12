# frozen_string_literal: true

require "test_helper"

# PremiumIdentities::Backfill imports identities that already exist as
# memberships, Gmail connections, redirect emails or WhatsApp claims.
class PremiumIdentitiesBackfillTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Backfill User",
      email: "backfill-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Backfill Test",
      code: "BACKFILL_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end

  test "imports memberships, Gmail, redirect email and WhatsApp identities" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.day.ago,
      expires_at: 1.month.from_now
    )
    GmailConnection.create!(user: @user, email: "backfill-inbox@gmail.com")
    EmailSource.create!(user: @user, source_type: "forwarding", email: "backfill-redirect@example.com",
                        status: "active")
    WhatsappIdentity.create!(phone_number: "+57 300 000 0000", claimed_by_user: @user, claimed_at: 1.day.ago)

    counts = PremiumIdentities::Backfill.call

    assert_equal 4, counts[:claimed]
    assert_equal 4, PremiumIdentity.count
    assert_equal %w[account_email gmail redirect_email whatsapp].sort,
                 PremiumIdentity.order(:identity_type).pluck(:identity_type)
  end

  test "is idempotent" do
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.day.ago,
      expires_at: 1.month.from_now
    )

    PremiumIdentities::Backfill.call

    assert_no_difference -> { PremiumIdentity.count } do
      PremiumIdentities::Backfill.call
    end
  end

  test "reports conflicts without aborting the rest of the backfill" do
    owner = User.create!(
      name: "Backfill Conflict Owner",
      email: "backfill.conflict+owner@gmail.com",
      password: "password123"
    )
    other = User.create!(
      name: "Backfill Conflict Other",
      email: "backfill.conflict+other@gmail.com",
      password: "password123"
    )
    [ owner, other ].each do |user|
      PaymentEngine::Membership.create!(
        owner: user,
        membership_type: @membership_type,
        status: "active",
        source: "purchase",
        starts_at: 1.day.ago,
        expires_at: 1.month.from_now
      )
    end
    PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: owner.email,
      user: owner
    )

    counts = PremiumIdentities::Backfill.call

    assert counts[:conflicts].positive?
    assert counts[:conflict_details].any? { |detail| detail[:user_id] == other.id }
  end
end

# frozen_string_literal: true

require "test_helper"

# WhatsappIdentity: the permanent, historical claim of a WhatsApp phone number
# by the first Expense Tracker account that connected it. It survives
# disconnects and account churn and backs the anti-abuse rule: a claimed
# number can never be re-claimed by a different account.
class WhatsappIdentityTest < ActiveSupport::TestCase
  test "normalize strips formatting and returns the E.164 number" do
    assert_equal "+573001234567", WhatsappIdentity.normalize("+57 300 123 4567")
    assert_equal "+573001234567", WhatsappIdentity.normalize("57-300-123-4567")
    assert_equal "+573001234567", WhatsappIdentity.normalize("573001234567")
    assert_equal "+573001234567", WhatsappIdentity.normalize("0057 300 123 4567")
  end

  test "wa_id returns the digits-only number used by WhatsApp" do
    assert_equal "573001234567", WhatsappIdentity.wa_id("+573001234567")
    assert_equal "573001234567", WhatsappIdentity.wa_id("573001234567")
  end

  test "phone_number is normalized before validation" do
    identity = WhatsappIdentity.new(phone_number: "+57 300 123 4567", claimed_at: Time.current)
    identity.valid?
    assert_equal "+573001234567", identity.phone_number
  end

  test "the same normalized number cannot create two identities" do
    first_user = User.create!(name: "First", email: "first_claim@example.com", password: "password123")
    second_user = User.create!(name: "Second", email: "second_claim@example.com", password: "password123")
    WhatsappIdentity.create!(phone_number: "573001234567", claimed_by_user: first_user, claimed_at: Time.current)

    second = WhatsappIdentity.new(phone_number: "+57 300 123 4567", claimed_by_user: second_user, claimed_at: Time.current)
    assert_not second.valid?
  end

  test "claim_for! creates the identity with the claiming user on first use" do
    user = User.create!(name: "Claimer", email: "claimer@example.com", password: "password123")

    identity = WhatsappIdentity.claim_for!(user, "+57 300 123 4567")

    assert_equal "+573001234567", identity.phone_number
    assert_equal user.id, identity.claimed_by_user_id
    assert identity.claimed_at.present?
  end

  test "claim_for! returns the existing identity when the number was already claimed" do
    owner = User.create!(name: "Owner", email: "owner_claim@example.com", password: "password123")
    other = User.create!(name: "Other", email: "other_claim@example.com", password: "password123")
    existing = WhatsappIdentity.claim_for!(owner, "573001234567")

    identity = WhatsappIdentity.claim_for!(other, "+57 300 123 4567")

    assert_equal existing.id, identity.id
    assert_equal owner.id, identity.claimed_by_user_id
    assert_equal 1, WhatsappIdentity.where(phone_number: "+573001234567").count
  end

  test "find_by resolves a raw wa_id through deterministic encryption" do
    user = User.create!(name: "Lookup", email: "lookup_claim@example.com", password: "password123")
    identity = WhatsappIdentity.claim_for!(user, "573001234567")

    found = WhatsappIdentity.find_by(phone_number: WhatsappIdentity.normalize("573001234567"))

    assert_equal identity.id, found.id
  end

  test "stores the phone number encrypted at rest" do
    user = User.create!(name: "Encrypted", email: "encrypted_claim@example.com", password: "password123")
    identity = WhatsappIdentity.claim_for!(user, "+57 300 123 4567")

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT phone_number FROM whatsapp_identities WHERE id = #{ActiveRecord::Base.connection.quote(identity.id)}"
    )

    assert_not_equal "+573001234567", raw
    assert_not_includes raw, "573001234567"
    assert_equal "+573001234567", identity.reload.phone_number
  end
end

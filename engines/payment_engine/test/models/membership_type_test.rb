require "test_helper"

class MembershipTypeTest < PaymentEngineTestCase
  test "creates a membership type with a unique slug" do
    type = create_membership_type(slug: "premium", description: "Paid access")

    assert_predicate type, :persisted?
    assert_equal "premium", type.slug
    assert_predicate type, :active?
  end

  test "rejects duplicated slugs" do
    create_membership_type(slug: "premium")
    duplicate = PaymentEngine::MembershipType.new(name: "Other", slug: "premium")

    refute duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "rejects invalid slug formats" do
    type = PaymentEngine::MembershipType.new(name: "Premium", slug: "Premium Plan")

    refute type.valid?
    assert type.errors[:slug].any?
  end

  test "deactivating a type does not revoke existing memberships" do
    type = create_membership_type(slug: "premium")
    owner = create_owner
    membership = create_membership(owner: owner, membership_type: type)

    type.update!(active: false)

    assert_predicate membership.reload, :active?
  end

  test "cannot delete a type with associated history" do
    type = create_membership_type(slug: "premium")
    create_payment_option(membership_type: type)

    refute type.destroy
    assert type.errors[:base].any?
    assert PaymentEngine::MembershipType.exists?(type.id)
  end

  test "can delete a type without history" do
    type = create_membership_type(slug: "temporary")

    assert type.destroy
    refute PaymentEngine::MembershipType.exists?(type.id)
  end
end

# frozen_string_literal: true

require "test_helper"

# Whatsapp::PremiumMembershipGate: blocks WhatsApp expense capture when the
# user has no active premium membership and throttles the single daily notice
# through Solid Cache, versioned by the membership's updated_at.
class WhatsappPremiumMembershipGateTest < ActiveSupport::TestCase
  PHONE_NUMBER = "573001112233"

  setup do
    @user = User.create!(
      name: "Premium Gate User",
      email: "premium_gate_#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "does not block when paid access is not required" do
    PaymentEngine::Setting.current.update!(paid_access_required: false)
    create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      assert_equal false, gate_blocks?(sent: sent)
    end

    assert_empty sent
  end

  test "does not block a user with an active membership" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "active", expires_at: 1.month.from_now)
    sent = []

    with_memory_cache do
      assert_equal false, gate_blocks?(sent: sent)
    end

    assert_empty sent
  end

  test "blocks an expired membership and sends a single notice" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      assert_equal true, gate_blocks?(sent: sent)
      assert_equal 1, sent.size

      assert_equal true, gate_blocks?(sent: sent)
      assert_equal 1, sent.size
    end

    assert_match(/membresía Premium/i, sent.first.last)
  end

  test "uses the localized notice text" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      I18n.with_locale(:en) do
        assert_equal true, gate_blocks?(sent: sent)
      end
    end

    assert_match(/Premium membership is not active/i, sent.first.last)
    assert_includes sent.first.last, AppName.current
  end

  test "stores the notice under a key scoped to the user and membership version" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    membership = create_membership(status: "expired", expires_at: 1.day.ago)
    expected_key = "premium_expired_notice:#{@user.id}:#{membership.updated_at.utc.iso8601(6)}"

    with_memory_cache do
      assert_equal true, gate_blocks?
      assert Rails.cache.exist?(expected_key), "expected cache key #{expected_key}"
    end
  end

  test "blocks a user without any membership using a stable key version" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    sent = []

    with_memory_cache do
      assert_equal true, gate_blocks?(sent: sent)
      assert Rails.cache.exist?("premium_expired_notice:#{@user.id}:none")
    end

    assert_equal 1, sent.size
  end

  test "sends a new notice after midnight" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      travel_to Time.zone.local(2026, 11, 11, 10, 0, 0) do
        assert_equal true, gate_blocks?(sent: sent)
      end

      travel_to Time.zone.local(2026, 11, 11, 23, 59, 0) do
        assert_equal true, gate_blocks?(sent: sent)
        assert_equal 1, sent.size
      end

      travel_to Time.zone.local(2026, 11, 12, 0, 0, 1) do
        assert_equal true, gate_blocks?(sent: sent)
        assert_equal 2, sent.size
      end
    end
  end

  test "a modified membership gets a new key and can notify again the same day" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    membership = create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      assert_equal true, gate_blocks?(sent: sent)
      assert_equal 1, sent.size

      travel_to 1.minute.from_now do
        membership.update!(expires_at: 2.days.ago)
        assert_equal true, gate_blocks?(sent: sent)
      end
    end

    assert_equal 2, sent.size
  end

  test "renewing the membership unblocks the user immediately" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    membership = create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      assert_equal true, gate_blocks?(sent: sent)

      travel_to 1.minute.from_now do
        membership.update!(status: "active", expires_at: 1.month.from_now)
        assert_equal false, gate_blocks?(sent: sent)
      end
    end

    assert_equal 1, sent.size
  end

  test "a failed notice delivery is retried on the next message" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "expired", expires_at: 1.day.ago)
    sent = []

    with_memory_cache do
      assert_equal true, gate_blocks?(deliver: false, sent: sent)
      assert_equal 1, sent.size

      assert_equal true, gate_blocks?(sent: sent)
      assert_equal 2, sent.size
    end
  end

  private

  def gate_blocks?(deliver: true, sent: [])
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) {
      sent << [ phone, text ]
      deliver
    }) do
      Whatsapp::PremiumMembershipGate.blocks?(user: @user, phone_number: PHONE_NUMBER)
    end
  end

  def create_membership(status:, expires_at:)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: membership_type,
      status: status,
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end

  def membership_type
    @membership_type ||= PaymentEngine::MembershipType.create!(
      name: "Premium Gate Test",
      code: "PREMIUM_GATE_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end

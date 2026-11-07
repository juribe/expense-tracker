# frozen_string_literal: true

require "test_helper"

class RecoveryCodeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Recovery Codes User",
      email: "recovery-codes-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @codes = RecoveryCode.generate_for(@user)
  end

  test "generates ten unique codes and stores only hashes" do
    assert_equal 10, @codes.size
    assert_equal 10, @codes.uniq.size
    assert_equal 10, @user.recovery_codes.count

    records = @user.recovery_codes.to_a
    @codes.each do |code|
      assert records.any? { |record| BCrypt::Password.new(record.code_digest).is_password?(code) }
      records.each do |record|
        refute_equal code, record.code_digest
        refute_includes record.attributes.values, code
      end
    end
  end

  test "consume marks a code as used and returns the record" do
    record = RecoveryCode.consume!(@user, @codes.first)

    assert record.present?
    assert record.reload.used_at.present?
    assert_equal @user, record.user
  end

  test "consume accepts a normalized version of the code" do
    code = @codes.first
    normalized = code.downcase.gsub(/[^a-z0-9]/, "")

    assert RecoveryCode.consume!(@user, normalized).present?
  end

  test "a consumed code cannot be used again" do
    assert RecoveryCode.consume!(@user, @codes.first).present?

    assert_nil RecoveryCode.consume!(@user, @codes.first)
  end

  test "unused scope excludes consumed codes" do
    used = RecoveryCode.consume!(@user, @codes.first)

    refute_includes RecoveryCode.unused.where(user: @user).to_a, used
    assert_equal 9, RecoveryCode.unused.where(user: @user).count
  end

  test "regenerating invalidates every previous code" do
    old_codes = @codes.dup
    old_digests = @user.recovery_codes.pluck(:code_digest)

    new_codes = RecoveryCode.generate_for(@user)

    assert_equal 10, @user.recovery_codes.count
    assert_equal 0, @user.recovery_codes.where(code_digest: old_digests).count
    old_codes.each { |code| assert_nil RecoveryCode.consume!(@user, code) }
    assert RecoveryCode.consume!(@user, new_codes.first).present?
  end

  test "invalid and blank codes return nil" do
    assert_nil RecoveryCode.consume!(@user, "")
    assert_nil RecoveryCode.consume!(@user, nil)
    assert_nil RecoveryCode.consume!(@user, "NOT-A-REAL-CODE")
    assert_equal 10, @user.recovery_codes.unused.count
  end

  test "a code from another user is rejected" do
    other_user = User.create!(
      name: "Other Recovery Codes User",
      email: "other-recovery-codes-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    other_code = RecoveryCode.generate_for(other_user).first

    assert_nil RecoveryCode.consume!(@user, other_code)
    assert_equal 10, @user.recovery_codes.unused.count
  end

  test "requires a code digest" do
    record = @user.recovery_codes.new

    refute record.valid?
    assert record.errors[:code_digest].present?
  end
end

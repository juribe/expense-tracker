# frozen_string_literal: true

require "test_helper"

# PendingWhatsappConnection: short-lived, single-use connect tokens shown in
# the Settings UI. Only a SHA-256 digest is persisted; the raw code lives
# exclusively in the UI for the 10 minutes the token is valid.
class PendingWhatsappConnectionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Pending User", email: "pending_user@example.com", password: "password123")
  end

  test "generate_for! returns the raw code and persists only the digest" do
    code = PendingWhatsappConnection.generate_for!(@user)

    assert_match(/\A[A-Z2-9]{5}\z/, code)
    pending_row = @user.pending_whatsapp_connections.last
    assert_equal PendingWhatsappConnection.digest_of(code), pending_row.token_digest
    assert_not_equal code, pending_row.token_digest
    assert_nil pending_row.used_at
    assert_in_delta 10.minutes.from_now, pending_row.expires_at, 5.seconds
  end

  test "valid_pending_for finds a fresh token by code" do
    code = PendingWhatsappConnection.generate_for!(@user)

    assert_equal @user.pending_whatsapp_connections.last.id, PendingWhatsappConnection.valid_pending_for(code)&.id
  end

  test "valid_pending_for ignores expired tokens" do
    code = nil
    travel_to 15.minutes.ago do
      code = PendingWhatsappConnection.generate_for!(@user)
    end

    assert_nil PendingWhatsappConnection.valid_pending_for(code)
  end

  test "valid_pending_for ignores already-used tokens" do
    code = PendingWhatsappConnection.generate_for!(@user)
    @user.pending_whatsapp_connections.last.update!(used_at: Time.current)

    assert_nil PendingWhatsappConnection.valid_pending_for(code)
  end

  test "consume! is atomic single-use" do
    code = PendingWhatsappConnection.generate_for!(@user)
    pending_row = @user.pending_whatsapp_connections.last

    assert pending_row.consume!
    assert pending_row.reload.used_at.present?
    assert_not pending_row.consume!
  end

  test "code comparison is case-insensitive" do
    code = PendingWhatsappConnection.generate_for!(@user)

    assert_equal @user.pending_whatsapp_connections.last.id, PendingWhatsappConnection.valid_pending_for(code.downcase)&.id
  end
end

# frozen_string_literal: true

require "test_helper"

# Whatsapp::ConnectService: handles the CONNECT <code> command received by the
# webhook. Covers the full connect/security matrix: first-time connect,
# invalid/expired/reused tokens, reconnection by the same owner, rejection of
# numbers already claimed by other accounts, and race-safe claiming.
class Whatsapp::ConnectServiceTest < ActiveSupport::TestCase
  OWNER_WA_ID = "573001234567"
  RIVAL_WA_ID = "573009999999"

  setup do
    @user = User.create!(name: "Connect User", email: "connect_service@example.com", password: "password123")
    @sent_replies = []
  end

  def connect_payload(wa_id: OWNER_WA_ID, text:)
    {
      object: "whatsapp_business_account",
      entry: [ {
        id: "waba_id",
        changes: [ {
          field: "messages",
          value: {
            messaging_product: "whatsapp",
            metadata: { display_phone_number: "5712345678", phone_number_id: "110497245015457" },
            contacts: [ { profile: { name: "Jose" }, wa_id: wa_id } ],
            messages: [ {
              id: "wamid.#{SecureRandom.hex(4)}",
              from: wa_id,
              timestamp: Time.current.to_i.to_s,
              type: "text",
              text: { body: text }
            } ]
          }
        } ]
      } ]
    }.to_json
  end

  def connect_event(wa_id: OWNER_WA_ID, text:)
    WhatsappPayload.new(connect_payload(wa_id: wa_id, text: text)).message_events.first
  end

  # Records the confirmation/instruction replies sent back over WhatsApp.
  # The replacement lambda must capture a local array: stub_method swaps the
  # receiver, so instance variables of the test would be invisible to it.
  def with_reply_stub
    replies = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone_number, text) { replies << [ phone_number, text ] }) do
      yield
    end
    @sent_replies = replies
  end

  test "1. first-time connect creates identity, active connection and consumes the token" do
    code = PendingWhatsappConnection.generate_for!(@user)
    pending_row = @user.pending_whatsapp_connections.last

    result = nil
    with_reply_stub do
      result = Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT #{code}"))
    end

    assert result.success?
    identity = WhatsappIdentity.find_by(phone_number: OWNER_WA_ID)
    assert_equal @user.id, identity.claimed_by_user_id
    assert result.result.active?
    assert_equal identity.id, result.result.whatsapp_identity_id
    assert_not_nil pending_row.reload.used_at
    assert @sent_replies.any? { |(phone, _)| phone == OWNER_WA_ID }
  end

  test "2. invalid token is rejected with a generic message and nothing is connected" do
    assert_no_difference [ -> { WhatsappIdentity.count }, -> { WhatsappConnection.count } ] do
      result = nil
      with_reply_stub do
        result = Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT ZZZZZ"))
      end

      assert result.failure?
      assert @sent_replies.any? { |(_, text)| text.present? }
    end
  end

  test "3. expired token is rejected" do
    code = nil
    travel_to 15.minutes.ago do
      code = PendingWhatsappConnection.generate_for!(@user)
    end

    assert_no_difference -> { WhatsappConnection.count } do
      result = nil
      with_reply_stub do
        result = Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT #{code}"))
      end

      assert result.failure?
    end
  end

  test "4. reused token is rejected" do
    code = PendingWhatsappConnection.generate_for!(@user)
    with_reply_stub do
      Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT #{code}"))
    end

    result = nil
    with_reply_stub do
      result = Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT #{code}"))
    end

    assert result.failure?
    assert_equal 1, WhatsappConnection.where(user: @user).count
  end

  test "5. the same owner can reconnect after disconnecting" do
    identity = WhatsappIdentity.claim_for!(@user, OWNER_WA_ID)
    first = WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: 1.day.ago)
    first.disconnect!
    code = PendingWhatsappConnection.generate_for!(@user)

    result = nil
    with_reply_stub do
      result = Whatsapp::ConnectService.call(event: connect_event(text: "connect #{code}"))
    end

    assert result.success?
    assert result.result.active?
    assert_equal identity.id, result.result.whatsapp_identity_id
    assert_equal 1, WhatsappIdentity.where(phone_number: OWNER_WA_ID).count
  end

  test "6. a number claimed by another account is rejected: no transfer, no second identity" do
    owner = User.create!(name: "Real Owner", email: "real_owner@example.com", password: "password123")
    WhatsappIdentity.claim_for!(owner, OWNER_WA_ID)
    code = PendingWhatsappConnection.generate_for!(@user)

    result = nil
    with_reply_stub do
      result = Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT #{code}"))
    end

    assert result.failure?
    identity = WhatsappIdentity.find_by(phone_number: OWNER_WA_ID)
    assert_equal owner.id, identity.claimed_by_user_id
    assert_equal 1, WhatsappIdentity.where(phone_number: OWNER_WA_ID).count
    assert_equal 0, WhatsappConnection.where(user: @user).count
    assert @sent_replies.any? { |(_, text)| text.include?("no se puede conectar") }
  end

  test "9. losing a claim race does not transfer ownership or duplicate identities" do
    owner = User.create!(name: "Race Owner", email: "race_owner@example.com", password: "password123")
    code = PendingWhatsappConnection.generate_for!(@user)

    # Simulate the concurrency loser: the INSERT loses the unique race but,
    # by the time the error is rescued, the winner's identity row exists.
    winner_created = false
    stub_method(WhatsappIdentity, :create!, lambda { |attrs|
      unless winner_created
        winner_created = true
        winner = WhatsappIdentity.new(phone_number: OWNER_WA_ID, claimed_by_user: owner, claimed_at: Time.current)
        winner.save!
        raise ActiveRecord::RecordNotUnique
      end
      identity = WhatsappIdentity.new(attrs)
      identity.save!
      identity
    }) do
      result = nil
      with_reply_stub do
        result = Whatsapp::ConnectService.call(event: connect_event(text: "CONNECT #{code}"))
      end

      assert result.failure?
    end

    identity = WhatsappIdentity.find_by(phone_number: OWNER_WA_ID)
    assert_equal owner.id, identity.claimed_by_user_id
    assert_equal 1, WhatsappIdentity.where(phone_number: OWNER_WA_ID).count
    assert_equal 0, WhatsappConnection.where(user: @user).count
  end
end

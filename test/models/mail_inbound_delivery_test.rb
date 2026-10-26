# frozen_string_literal: true

require "test_helper"

class MailInboundDeliveryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Inbound Delivery", email: "inbound_delivery_test@example.com", password: "password123")
    @delivery = MailInboundDelivery.new(
      user: @user,
      provider: "cloudflare",
      external_id: "abc123",
      raw_body: "From: bank@example.com\r\n\r\nHello"
    )
  end

  test "is valid with provider, external id and user" do
    assert @delivery.valid?
    assert_equal "received", @delivery.status
  end

  test "requires a known provider and status" do
    @delivery.provider = "unknown"
    assert_not @delivery.valid?

    @delivery.provider = "cloudflare"
    @delivery.status = "unknown"
    assert_not @delivery.valid?
  end

  test "enforces unique provider and external id" do
    @delivery.save!

    duplicate = MailInboundDelivery.new(
      user: @user, provider: "cloudflare", external_id: "abc123", raw_body: "other"
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "tracks handling, success and failure" do
    @delivery.save!

    @delivery.handling!
    assert_equal "handling", @delivery.status
    assert_equal 1, @delivery.attempts

    processed = ProcessedEmail.create!(
      user: @user, provider: "cloudflare", message_id: "abc123", status: "queued"
    )
    @delivery.handled!(processed)
    assert_equal "handled", @delivery.status
    assert_equal processed, @delivery.processed_email

    @delivery.failed!("boom")
    assert_equal "failed", @delivery.status
    assert_equal "boom", @delivery.last_error
  end
end

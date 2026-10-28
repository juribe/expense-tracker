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

  test "handled! removes the raw email while keeping routing data" do
    @delivery.headers = { "from" => "bank@example.com" }
    @delivery.params = { "body" => "Compra" }
    @delivery.save!
    processed = ProcessedEmail.create!(
      user: @user, provider: "cloudflare", message_id: "abc123", status: "queued"
    )

    @delivery.handled!(processed)

    @delivery.reload
    assert_nil @delivery.raw_body
    assert_equal({}, @delivery.headers)
    assert_equal({}, @delivery.params)
    assert_equal "abc123", @delivery.external_id
    assert_equal processed, @delivery.processed_email
    assert_equal "handled", @delivery.status
  end

  test "purge_email_content! clears stored content and is idempotent" do
    @delivery.headers = { "from" => "bank@example.com" }
    @delivery.params = { "body" => "Compra" }
    @delivery.save!

    @delivery.purge_email_content!
    @delivery.purge_email_content!

    @delivery.reload
    assert_nil @delivery.raw_body
    assert_equal({}, @delivery.headers)
    assert_equal({}, @delivery.params)
    assert_equal "abc123", @delivery.external_id
  end
end

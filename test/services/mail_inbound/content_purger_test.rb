# frozen_string_literal: true

require "test_helper"

class MailInboundContentPurgerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Content Purger",
      email: "mail_inbound_content_purger_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @delivery = MailInboundDelivery.create!(
      user: @user,
      provider: "cloudflare",
      external_id: "purge-handled",
      raw_body: "From: bank@example.com\r\n\r\nCompra",
      headers: { "from" => "bank@example.com" },
      params: { "body" => "Compra" },
      status: "handled"
    )
    @pending_delivery = MailInboundDelivery.create!(
      user: @user,
      provider: "cloudflare",
      external_id: "purge-pending",
      raw_body: "From: bank@example.com\r\n\r\nCompra",
      status: "received"
    )
    @old_failed_delivery = MailInboundDelivery.create!(
      user: @user,
      provider: "cloudflare",
      external_id: "purge-old-failed-delivery",
      raw_body: "From: bank@example.com\r\n\r\nCompra",
      status: "failed"
    )
    @old_failed_delivery.update_columns(updated_at: 2.days.ago)
    @recent_failed_delivery = MailInboundDelivery.create!(
      user: @user,
      provider: "cloudflare",
      external_id: "purge-recent-failed-delivery",
      raw_body: "From: bank@example.com\r\n\r\nCompra",
      status: "failed"
    )
    @processed = processed_email("purge-processed", "processed")
    @review = processed_email(
      "purge-review",
      "needs_review",
      "email" => { "body_text" => "Compra" },
      "subject" => "Compra aprobada",
      "transactions" => [ { "amount" => 48_500 } ]
    )
    @queued = processed_email("purge-queued", "queued")
    @old_failed = processed_email("purge-old-failed", "failed")
    @old_failed.update_columns(updated_at: 2.days.ago)
    @recent_failed = processed_email("purge-recent-failed", "failed")
    @gmail_review = ProcessedEmail.create!(
      user: @user,
      provider: "gmail",
      message_id: "purge-gmail-review",
      status: "needs_review",
      payload: JSON.generate("subject" => "Compra", "transactions" => [ { "amount" => 1_000 } ])
    )
  end

  test "dry run reports content without modifying rows" do
    counts = MailInbound::ContentPurger.new(dry_run: true).run

    assert_equal 2, counts[:deliveries]
    assert_equal 3, counts[:processed_emails]
    assert @delivery.reload.raw_body.present?
    assert @old_failed_delivery.reload.raw_body.present?
    assert @processed.reload.payload_data["email"].present?
  end

  test "purges handled deliveries and terminal processed emails" do
    counts = MailInbound::ContentPurger.new.run

    assert_equal 2, counts[:deliveries]
    assert_equal 3, counts[:processed_emails]

    @delivery.reload
    assert_nil @delivery.raw_body
    assert_equal({}, @delivery.headers)
    assert_equal({}, @delivery.params)

    assert_nil @processed.reload.payload_data["email"]
    assert_nil @review.reload.payload_data["email"]
    assert_equal "Compra aprobada", @review.payload_data["subject"]
    assert_equal [ { "amount" => 48_500 } ], @review.payload_data["transactions"]
    assert_nil @old_failed.reload.payload_data["email"]
    assert_nil @old_failed_delivery.reload.raw_body
  end

  test "keeps content that may still be processed or retried" do
    MailInbound::ContentPurger.new.run

    assert @pending_delivery.reload.raw_body.present?
    assert @recent_failed_delivery.reload.raw_body.present?
    assert @queued.reload.payload_data["email"].present?
    assert @recent_failed.reload.payload_data["email"].present?
    assert_equal "Compra", @gmail_review.reload.payload_data["subject"]
  end

  test "is idempotent" do
    MailInbound::ContentPurger.new.run
    counts = MailInbound::ContentPurger.new.run

    assert_equal 0, counts[:deliveries]
    assert_equal 0, counts[:processed_emails]
  end

  private

  def processed_email(message_id, status, payload = { "email" => { "body_text" => "Compra" } })
    ProcessedEmail.create!(
      user: @user,
      provider: "cloudflare",
      message_id: message_id,
      status: status,
      payload: JSON.generate(payload)
    )
  end
end

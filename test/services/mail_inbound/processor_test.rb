# frozen_string_literal: true

require "test_helper"

class MailInbound::ProcessorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Mail Inbound Processor", email: "mail_inbound_processor@example.com", password: "password123")
    Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    @money_source = @user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")
    @message = {
      id: "inbound-processor@example.com",
      from: "Banco <notificaciones@bank.example>",
      to: [ "receive+user1@samyreplies.com" ],
      subject: "Compra aprobada",
      body_text: "Compra realizada por $48.500 en RESTAURANTE XYZ con tarjeta terminada en 1234.",
      html: "<p>Compra realizada por $48.500 en RESTAURANTE XYZ.</p>",
      internal_date: "2026-08-23T14:30:00Z",
      headers: [ { "name" => "From", "value" => "Banco <notificaciones@bank.example>" } ],
      attachments: []
    }
    @record = ProcessedEmail.create!(
      user: @user,
      provider: "cloudflare",
      message_id: @message[:id],
      status: "queued",
      payload: JSON.generate("email" => @message.deep_stringify_keys.as_json)
    )
  end

  class FakeDetector
    def initialize(transactional: true, reason: nil)
      @result = EmailTransactionDetector::Result.new(transactional?: transactional, reason: reason)
    end

    def call(subject:, body:)
      @result
    end
  end

  class FakeExtractor
    def initialize(result)
      @result = result
    end

    def call(subject:, body:, today:, categories: [])
      @result
    end
  end

  def transaction(overrides = {})
    {
      type: "expense",
      amount: BigDecimal("48500"),
      currency: "COP",
      merchant: "Restaurante XYZ",
      category: "restaurants",
      occurred_at: "2026-08-23T14:30:00Z",
      confidence: 0.98,
      card_last_four: "1234",
      bank: "Bank"
    }.merge(overrides)
  end

  def extraction(transactions:, should_ignore: false, reason: nil)
    { ok?: true, data: { transactions: transactions, should_ignore: should_ignore, reason: reason }, error: nil }
  end

  def processor(detector: FakeDetector.new, extractor: FakeExtractor.new(extraction(transactions: [ transaction ])))
    MailInbound::Processor.new(
      user: @user,
      provider: "cloudflare",
      detector: detector,
      extractor: extractor
    )
  end

  test "creates an expense through the existing import pipeline" do
    result = processor.call(@message)

    assert_equal :processed, result.status
    expense = Expense.find(result.expense_ids.first)
    assert_equal "cloudflare", expense.source
    assert_equal @message[:id], expense.gmail_message_id
    assert_equal @money_source, expense.money_source
    assert_equal "processed", @record.reload.status
  end

  test "a retry does not create a second expense" do
    processor.call(@message)
    second = processor.call(@message)

    assert_equal :skipped, second.status
    assert_equal 1, Expense.where(gmail_message_id: @message[:id]).count
  end

  test "keeps the stored email when confidence routes it to review" do
    low_confidence = FakeExtractor.new(extraction(transactions: [ transaction(confidence: 0.4) ]))

    result = processor(extractor: low_confidence).call(@message)

    assert_equal :needs_review, result.status
    assert_equal "needs_review", @record.reload.status
    assert_equal @message[:subject], @record.payload_data.dig("email", "subject")
    assert_equal 0.4, @record.payload_data.dig("transactions", 0, "confidence")
  end

  test "a failed extraction can be retried successfully" do
    broken = FakeExtractor.new({ ok?: false, data: nil, error: "AI down" })
    failed = processor(extractor: broken).call(@message)

    assert_equal :failed, failed.status
    assert_equal "failed", @record.reload.status

    retried = processor.call(@message)

    assert_equal :processed, retried.status
    assert_equal 1, Expense.where(gmail_message_id: @message[:id]).count
  end
end

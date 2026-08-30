# frozen_string_literal: true

require "test_helper"

module Gmail
  class ExpenseImporterTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Importer User", email: "gmail_importer_test@example.com", password: "password123")
      Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
      @connection = GmailConnection.create!(user: @user, email: "me@gmail.com")
      @message = {
        id: "msg-100",
        subject: "Compra aprobada",
        body_text: "Compra realizada por $48.500 en RESTAURANTE XYZ con tarjeta terminada en 1234.",
        internal_date: Time.zone.parse("2026-08-23T14:30:00"),
        snippet: ""
      }
    end

    def transaction(overrides = {})
      {
        type: "expense",
        amount: BigDecimal(48_500.to_s),
        currency: "COP",
        merchant: "Restaurante XYZ",
        category: "restaurants",
        occurred_at: "2026-08-23T14:30:00",
        confidence: 0.98,
        card_last_four: "1234",
        bank: "Bancolombia"
      }.merge(overrides)
    end

    def detector_result(transactional:, reason: nil)
      EmailTransactionDetector::Result.new(transactional?: transactional, reason: reason)
    end

    def importer(detector: nil, extractor: nil)
      Gmail::ExpenseImporter.new(
        connection: @connection,
        detector: detector || FakeDetector.new(detector_result(transactional: true)),
        extractor: extractor || FakeExtractor.new({ ok?: true, data: { transactions: [ transaction ], should_ignore: false, reason: nil }, error: nil })
      )
    end

    class FakeDetector
      def initialize(result)
        @result = result
      end

      def call(subject:, body:)
        @result
      end
    end

    class FakeExtractor
      def initialize(result)
        @result = result
      end

      def call(subject:, body:, today:)
        @result
      end
    end

    test "creates an expense and marks the email as processed" do
      result = importer.call(@message)

      assert_equal :processed, result.status
      expense = Expense.find(result.expense_ids.first)
      assert_equal "gmail", expense.source
      assert_equal "msg-100", expense.gmail_message_id
      assert_equal "Restaurante XYZ", expense.description

      processed = ProcessedEmail.find_by(provider: "gmail", message_id: "msg-100")
      assert_not_nil processed
      assert_equal "processed", processed.status
      assert_equal expense.id, processed.expense_id
    end

    test "assigns the money source when exactly one source matches" do
      source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      source.tags.create!(value: "1234")

      result = importer.call(@message)

      assert_equal :processed, result.status
      assert_equal source, Expense.find(result.expense_ids.first).money_source
    end

    test "does not auto-assign a money source when the match is ambiguous" do
      @user.money_sources.create!(name: "Source A", kind: "credit_card").tags.create!(value: "1234")
      @user.money_sources.create!(name: "Source B", kind: "credit_card").tags.create!(value: "1234")

      result = importer.call(@message)

      assert_equal :processed, result.status
      assert_nil Expense.find(result.expense_ids.first).money_source
    end

    test "never processes the same message twice" do
      importer.call(@message)

      result = importer.call(@message)
      assert_equal :skipped, result.status
      assert_equal 1, ProcessedEmail.gmail.count
      assert_equal 1, Expense.where(gmail_message_id: "msg-100").count
    end

    test "queues low-confidence transactions for review instead of creating expenses" do
      low = importer(
        extractor: FakeExtractor.new({ ok?: true, data: { transactions: [ transaction(confidence: 0.4) ], should_ignore: false, reason: nil }, error: nil })
      )

      result = low.call(@message)
      assert_equal :needs_review, result.status
      assert_empty result.expense_ids
      assert_equal 0, Expense.where(gmail_message_id: "msg-100").count

      review = ProcessedEmail.gmail.needs_review.last
      stored = review.payload_data["transactions"].first
      assert_in_delta 0.4, stored["confidence"], 0.001
    end

    test "records ignored emails without creating expenses" do
      non_transactional = importer(detector: FakeDetector.new(detector_result(transactional: false, reason: "promotion or marketing")))

      result = non_transactional.call(@message)
      assert_equal :ignored, result.status
      assert_equal 0, Expense.count

      record = ProcessedEmail.find_by(provider: "gmail", message_id: "msg-100")
      assert_equal "ignored", record.status
      assert_equal "promotion or marketing", record.failure_reason
    end

    test "ignores emails the AI flags with should_ignore" do
      ignored = importer(extractor: FakeExtractor.new({ ok?: true, data: { transactions: [], should_ignore: true, reason: "balance notification" }, error: nil }))

      result = ignored.call(@message)
      assert_equal :ignored, result.status
      assert_equal "balance notification", result.reason
      assert_equal 0, Expense.count
    end

    test "marks extraction failures as failed without raising" do
      broken = importer(extractor: FakeExtractor.new({ ok?: false, data: nil, error: "invalid AI response" }))

      result = broken.call(@message)
      assert_equal :failed, result.status
      assert_equal 0, Expense.count

      record = ProcessedEmail.find_by(provider: "gmail", message_id: "msg-100")
      assert_equal "failed", record.status
      assert_equal "invalid AI response", record.failure_reason
      assert_operator record.attempts, :>=, 1
    end

    test "failed records can be retried and later succeed" do
      broken = importer(extractor: FakeExtractor.new({ ok?: false, data: nil, error: "AI down" }))
      broken.call(@message)

      working = importer(
        extractor: FakeExtractor.new({ ok?: true, data: { transactions: [ transaction ], should_ignore: false, reason: nil }, error: nil })
      )
      result = working.call(@message)
      assert_equal :processed, result.status

      record = ProcessedEmail.find_by(provider: "gmail", message_id: "msg-100")
      assert_equal "processed", record.status
      assert_equal 2, record.attempts
    end

    test "handles multiple transactions in a single email" do
      multi = importer(
        extractor: FakeExtractor.new({ ok?: true, data: { transactions: [ transaction, transaction(merchant: "Cafe X", amount: BigDecimal(9000.to_s)) ], should_ignore: false, reason: nil }, error: nil })
      )
      result = multi.call(@message)

      assert_equal 2, result.expense_ids.size
      assert_equal 2, Expense.where(gmail_message_id: "msg-100").count
    end

    test "skips non-expense types such as refunds reported by the AI" do
      refund = importer(
        extractor: FakeExtractor.new({ ok?: true, data: { transactions: [ transaction(type: "refund") ], should_ignore: false, reason: nil }, error: nil })
      )
      result = refund.call(@message)

      assert_equal :processed, result.status
      assert_empty result.expense_ids
      assert_match(/refund/, result.reason)
      assert_equal 0, Expense.count
    end

    test "records failures when the expense cannot be created" do
      invalid = importer(
        extractor: FakeExtractor.new({ ok?: true, data: { transactions: [ transaction(amount: BigDecimal(0.to_s)) ], should_ignore: false, reason: nil }, error: nil })
      )
      result = invalid.call(@message)

      assert_equal :failed, result.status
      assert_equal 0, Expense.count
      assert_match(/amount/i, ProcessedEmail.find_by(message_id: "msg-100").failure_reason)
    end
  end
end

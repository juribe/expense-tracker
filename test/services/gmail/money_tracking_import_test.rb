# frozen_string_literal: true

require "test_helper"

module Gmail
  class MoneyTrackingImportTest < ActiveSupport::TestCase
    setup do
      @category = Category.create!(name: "Gmail Tracking", is_default: true, category_type: "expense")
      @message = {
        id: "msg-tracking-1",
        subject: "Compra aprobada",
        body_text: "Compra realizada por $48.500 en RESTAURANTE XYZ con tarjeta terminada en 1234.",
        internal_date: Time.zone.parse("2026-08-23T14:30:00"),
        snippet: ""
      }
    end

    test "simple mode imports the email into General without source recognition" do
      user = simple_user
      general = user.general_money_source
      connection = GmailConnection.create!(user: user, email: "simple-gmail@example.com")

      result = importer(connection).call(@message)

      assert_equal :processed, result.status
      expense = Expense.find(result.expense_ids.first)
      assert_equal general.id, expense.money_source_id
      assert_equal "gmail", expense.source
    end

    test "advanced mode keeps the recognized source" do
      user = detailed_user
      visa = user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")
      connection = GmailConnection.create!(user: user, email: "advanced-gmail@example.com")

      result = importer(connection).call(@message)

      assert_equal :processed, result.status
      expense = Expense.find(result.expense_ids.first)
      assert_equal visa.id, expense.money_source_id
    end

    private

    def importer(connection)
      Gmail::ExpenseImporter.new(
        connection: connection,
        detector: FakeDetector.new(EmailTransactionDetector::Result.new(transactional?: true, reason: nil)),
        extractor: FakeExtractor.new(
          ok?: true,
          data: { transactions: [ transaction ], should_ignore: false, reason: nil },
          error: nil
        )
      )
    end

    def transaction
      {
        type: "expense",
        amount: BigDecimal("48500"),
        currency: "COP",
        merchant: "Restaurante XYZ",
        category: "Gmail Tracking",
        occurred_at: "2026-08-23T14:30:00",
        confidence: 0.98,
        card_last_four: "1234",
        bank: "Bancolombia"
      }
    end

    def simple_user
      user = User.create!(name: "Simple Gmail", email: "simple_gmail_#{SecureRandom.hex(4)}@example.com",
                          password: "password123")
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      user.ensure_general_money_source!
      user
    end

    def detailed_user
      User.create!(name: "Advanced Gmail", email: "advanced_gmail_#{SecureRandom.hex(4)}@example.com",
                   password: "password123")
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

      def call(subject:, body:, today:, categories: [])
        @result
      end
    end
  end
end

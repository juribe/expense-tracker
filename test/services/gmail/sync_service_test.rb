# frozen_string_literal: true

require "test_helper"
require "logger"

module Gmail
  class SyncServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Sync User", email: "gmail_sync_test@example.com", password: "password123")
      Category.create!(name: "Restaurants")
      @connection = GmailConnection.create!(user: @user, email: "me@gmail.com")
    end

    # Fake Gmail API client returning canned data.
    class FakeClient
      class << self
        attr_accessor :stubs, :fail_on

        def configure(stubs:, fail_on: [])
          self.stubs = stubs
          self.fail_on = Array(fail_on)
          self
        end
      end

      def initialize(_connection); end

      def list_messages(query:, max_results: 25)
        @queries ||= []
        @queries << { query: query, max_results: max_results }
        stubs.keys.map { |id| { "id" => id } }
      end

      def get_message(message_id)
        raise Gmail::Client::Error, "boom" if fail_on.include?(message_id)

        stubs.fetch(message_id)
      end

      def stubs = self.class.stubs

      def fail_on = self.class.fail_on
    end

    # Always succeeds with one high-confidence restaurant purchase.
    class FakeExtractor
      RESULT = {
        ok?: true,
        data: {
          transactions: [ {
            type: "expense",
            amount: BigDecimal(48_500.to_s),
            currency: "COP",
            merchant: "Restaurante XYZ",
            category: "restaurants",
            occurred_at: "2026-08-23T14:30:00",
            confidence: 0.98,
            card_last_four: "1234",
            bank: nil
          } ],
          should_ignore: false,
          reason: nil
        },
        error: nil
      }.freeze

      def call(subject:, body:, today:)
        RESULT
      end
    end

    def purchase_message(id)
      {
        id: id,
        subject: "Compra aprobada",
        body_text: "Compra realizada por $48.500 en RESTAURANTE XYZ.",
        internal_date: Time.zone.parse("2026-08-23T14:30:00"),
        snippet: ""
      }
    end

    def sync(client_class)
      logger = Logger.new(StringIO.new)
      Gmail::SyncService.call(@connection.reload, client_class: client_class, extractor: FakeExtractor.new, logger: logger)
    end

    test "imports fetched messages and updates last_synced_at" do
      summary = sync(FakeClient.configure(stubs: { "a" => purchase_message("a"), "b" => purchase_message("b") }))

      assert_equal 2, summary[:fetched]
      assert_equal 2, summary[:created]
      assert_equal 2, Expense.where(source: "gmail").count
      assert_not_nil @connection.reload.last_synced_at
    end

    test "continues processing when one message fails and logs it as failed" do
      summary = sync(FakeClient.configure(
                       stubs: { "bad" => purchase_message("bad"), "good" => purchase_message("good") },
                       fail_on: [ "bad" ]
                     ))

      assert_equal 1, summary[:failed]
      assert_equal 1, summary[:created]

      failed_record = ProcessedEmail.find_by(provider: "gmail", message_id: "bad")
      assert_equal "failed", failed_record.status
      assert_match(/boom/, failed_record.failure_reason)
    end

    test "does nothing for inactive connections" do
      @connection.update!(active: false)

      summary = sync(FakeClient.configure(stubs: {}))
      assert_equal 0, summary[:fetched]
      assert_nil @connection.reload.last_synced_at
    end

    test "reports api errors without raising" do
      failing_class = Class.new(Gmail::Client) do
        def list_messages(query:, max_results: 25)
          raise Gmail::OauthClient::Error, "invalid credentials"
        end
      end

      summary = sync(failing_class)
      assert_equal({ created: 0, failed: 0, fetched: 0, ignored: 0, needs_review: 0, skipped: 0 }, summary.except(:error))
      assert_equal "invalid credentials", summary[:error]
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require "logger"

module Gmail
  class SyncServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Sync User", email: "gmail_sync_test@example.com", password: "password123")
      Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
      @user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")
      @connection = GmailConnection.create!(user: @user, email: "me@gmail.com",
                                           search_config: { senders: [ "notifications@bank.com" ],
                                                            subject_keywords: [ "compra" ] })    end

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

      def call(subject:, body:, today:, categories: [])
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

    test "does not downgrade an already processed message when fetching it fails" do
      record = ProcessedEmail.create!(user: @user, provider: "gmail", message_id: "done",
                                     status: "processed", attempts: 2, processed_at: 1.day.ago)

      sync(FakeClient.configure(stubs: { "done" => purchase_message("done") }, fail_on: [ "done" ]))

      record.reload
      assert_equal "processed", record.status
      assert_equal 2, record.attempts
    end

    test "does not downgrade a message pending review when fetching it fails" do
      record = ProcessedEmail.create!(user: @user, provider: "gmail", message_id: "review",
                                     status: "needs_review", attempts: 1, processed_at: 1.day.ago)

      sync(FakeClient.configure(stubs: { "review" => purchase_message("review") }, fail_on: [ "review" ]))

      assert_equal "needs_review", record.reload.status
    end

    test "syncs the same message id independently for different users" do
      other_user = User.create!(name: "Other Sync", email: "gmail_sync_other@example.com",
                                password: "password123")
      other_user.money_sources.create!(name: "Visa Other", kind: "credit_card", identifier: "1234")
      other_connection = GmailConnection.create!(user: other_user, email: "other@gmail.com",
                                                 search_config: { senders: [ "notifications@bank.com" ] })
      client_class = FakeClient.configure(stubs: { "same" => purchase_message("same") })
      logger = Logger.new(StringIO.new)

      Gmail::SyncService.call(@connection.reload, client_class: client_class,
                              extractor: FakeExtractor.new, logger: logger)
      Gmail::SyncService.call(other_connection.reload, client_class: client_class,
                              extractor: FakeExtractor.new, logger: logger)

      assert_equal 2, ProcessedEmail.where(provider: "gmail", message_id: "same").count
      assert_equal 1, Expense.where(user: @user, gmail_message_id: "same").count
      assert_equal 1, Expense.where(user: other_user, gmail_message_id: "same").count
    end

    test "does not mark another user's message as failed" do
      other_user = User.create!(name: "Other Failure", email: "gmail_sync_failure@example.com",
                                password: "password123")
      foreign = ProcessedEmail.create!(user: other_user, provider: "gmail", message_id: "bad",
                                       status: "processing", attempts: 1)

      sync(FakeClient.configure(stubs: { "bad" => purchase_message("bad") }, fail_on: [ "bad" ]))

      foreign.reload
      assert_equal "processing", foreign.status
      assert_equal 1, foreign.attempts
      own = ProcessedEmail.find_by!(user: @user, provider: "gmail", message_id: "bad")
      assert_equal "failed", own.status
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
      assert_equal({ created: 0, failed: 0, fetched: 0, ignored: 0, needs_review: 0, skipped: 0, suggestions: 0 },
                   summary.except(:error))
      assert_equal "invalid credentials", summary[:error]
    end

    test "first sync runs recognition discovery and reports the suggestions created" do
      require Rails.root.join("db/seed_data/financial_catalog_seeder")
      FinancialCatalogSeeder.run
      source = @user.money_sources.create!(name: "Davibank Clásica", kind: "account",
                                           starting_balance: 0, bank: "Davibank", identifier: "5678")

      message = purchase_message("davi")
      message[:from] = "Davibank <notificaciones@davibank.com>"
      message[:subject] = "Transacción aprobada"
      message[:body_text] = "DAVIbank te notifica: transacción con tu tarjeta Clasica terminada en 5678."

      summary = sync(FakeClient.configure(stubs: { "davi" => message }))

      # sender + domain + subject + keywords (davibank, clasica, 5678)
      assert_equal 6, summary[:suggestions]
      source.reload
      assert_empty source.recognition_identifiers.confirmed
      assert source.recognition_identifiers.suggested.exists?(kind: "sender", value: "notificaciones@davibank.com")
      assert source.recognition_identifiers.suggested.exists?(kind: "keyword", value: "5678")
    end

    test "discovery failures never abort the sync" do
      @user.money_sources.create!(name: "Davibank Clásica", kind: "account", starting_balance: 0, bank: "Davibank")
      failing_discovery = Object.new
      failing_discovery.define_singleton_method(:process) { |*| raise StandardError, "discovery boom" }
      stub_method(SourceRecognition::DiscoveryService, :new, ->(*) { failing_discovery }) do
        summary = sync(FakeClient.configure(stubs: { "a" => purchase_message("a") }))

        assert_equal 1, summary[:created]
        assert_equal 0, summary[:suggestions]
      end
    end
  end
end

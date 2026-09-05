# frozen_string_literal: true

require "test_helper"
require "logger"

module Gmail
  class SetupScanServiceTest < ActiveSupport::TestCase
    setup do
      require Rails.root.join("db/seed_data/financial_catalog_seeder")
      FinancialCatalogSeeder.run

      @user = User.create!(name: "Setup User", email: "setup_scan_test@example.com", password: "password123")
      @user.money_sources.create!(name: "Davibank Clásica", kind: "account",
                                  starting_balance: 0, bank: "Davibank", identifier: "5678")
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

    def davibank_message(id: "m1", subject: "Transacción aprobada por $50.000 en Tienda X")
      {
        id: id,
        from: "Davibank <notificaciones@davibank.com>",
        subject: subject,
        body_text: "DAVIbank te notifica que realizaste con tu tarjeta Clasica " \
                   "una transacción de 20,300 con la tarjeta terminada en 5678."
      }
    end

    def marketing_message(id: "m2")
      {
        id: id,
        from: "Davibank <promos@davibank.com>",
        subject: "Promoción exclusiva para ti",
        body_text: "DAVIbank descuento exclusiva: abre tu cuenta y aprovecha la promoción."
      }
    end

    test "aggregates settings suggestions from financial emails and runs discovery" do
      FakeClient.configure(stubs: { "m1" => davibank_message, "m2" => marketing_message })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert_equal 2, result[:scanned]
      assert_equal 1, result[:passed]
      assert_equal [ { "value" => "notificaciones@davibank.com", "count" => 1 } ],
                   result[:senders].map { |s| { "value" => s[:value], "count" => s[:count] } }
      assert_includes result[:domains].map { |d| d[:value] }, "davibank.com"
      assert result[:subject_keywords].any? { |k| k[:value].in?([ "transacción", "transaccion" ]) }

      # Persisted for the setup page (step 1 of the wizard).
      stored = @connection.reload.setup_suggestions
      assert_equal 1, stored["passed"]
      assert stored["senders"].present?

      # Discovery ran for the financial email (step 2 of the wizard).
      assert result[:suggestions].positive?
      assert @user.money_sources.first.recognition_identifiers.exists?
    end

    test "one broken message never aborts the scan" do
      FakeClient.configure(stubs: { "m1" => davibank_message }, fail_on: [ "m1" ])

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert_equal 1, result[:scanned]
      assert_equal 0, result[:passed]
      assert_empty result[:senders]
    end

    test "no imports happen during setup scan" do
      FakeClient.configure(stubs: { "m1" => davibank_message })

      assert_no_difference "Expense.count" do
        assert_no_difference "ProcessedEmail.count" do
          SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))
        end
      end
    end

    test "inactive connection is a no-op" do
      @connection.update!(active: false)
      FakeClient.configure(stubs: { "m1" => davibank_message })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert result[:error].blank? || result[:scanned] == 0
      assert_nil @connection.reload.setup_suggestions
    end
  end
end

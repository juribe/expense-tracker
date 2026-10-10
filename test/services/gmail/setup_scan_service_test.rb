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

    def bank_message(id: "m1", subject: "Transacción aprobada por $50.000 en Tienda X",
                     sender: "notificaciones@davibank.com", card: "Clasica", last_four: "5678")
      {
        id: id,
        from: "Davibank <#{sender}>",
        subject: subject,
        body_text: "DAVIbank te notifica que realizaste con tu tarjeta #{card} " \
                   "una transacción de 20,300 con la tarjeta terminada en #{last_four}."
      }
    end

    def marketing_message(id: "m2", sender: "promos@davibank.com")
      {
        id: id,
        from: "Davibank <#{sender}>",
        subject: "Promoción exclusiva para ti",
        body_text: "DAVIbank descuento exclusiva: abre tu cuenta y aprovecha la promoción."
      }
    end

    test "aggregates settings suggestions from financial emails and runs discovery" do
      FakeClient.configure(stubs: { "m1" => bank_message })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert_equal 1, result[:scanned]
      assert_equal 1, result[:passed]
      # A sender seen once is not a reusable pattern yet: below the threshold.
      assert_empty result[:senders].select { |s| s[:value] == "notificaciones@davibank.com" }
      assert_includes result[:domains].map { |d| d[:value] }, "davibank.com"
      assert result[:subject_keywords].any? { |k| k[:value].in?([ "transacción", "transaccion" ]) }

      # Persisted for the recognition page.
      stored = @connection.reload.setup_suggestions
      assert_equal 1, stored["passed"]
      assert stored["domains"].present?

      # Discovery ran for the financial email (money source suggestions).
      assert result[:suggestions].positive?
      assert @user.money_sources.first.recognition_identifiers.exists?
    end

    test "only senders seen at least twice are suggested as reusable patterns" do
      FakeClient.configure(stubs: {
        "m1" => bank_message(id: "m1", subject: "Transacción aprobada por $50.000 en A"),
        "m2" => bank_message(id: "m2", subject: "Transacción aprobada por $10.000 en B"),
        "m3" => bank_message(id: "m3", subject: "Notificación de saldo", sender: "una-vez@davibank.com"),
        "m4" => marketing_message(id: "m4"),
        "m5" => bank_message(id: "m5", subject: "Promoción exclusiva para ti", sender: "promos@otroban.com")
                                  .merge(body_text: "Davienda tiene una promoción para ti, abre tu cuenta"),
        "m6" => bank_message(id: "m6", subject: "Te quedan pocos días", sender: "campanas@otroban.com")
                                  .merge(body_text: "Davienda registrate y aprovecha el descuento exclusivo")
      })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      senders = result[:senders].map { |s| { "value" => s[:value], "count" => s[:count] } }
      # Marketing senders are filtered out even when repeated.
      assert_equal [ { "value" => "notificaciones@davibank.com", "count" => 2 } ], senders
      refute result[:domains].any? { |d| d[:value].end_with?("otroban.com") }
    end

    test "recurring subjects become reusable templates with counts and institution" do
      FakeClient.configure(stubs: {
        "m1" => bank_message(id: "m1", subject: "Transacción aprobada por $50.000 en Tienda X"),
        "m2" => bank_message(id: "m2", subject: "Re:  Transacción aprobada por $10.000 en Otro"),
        "m3" => bank_message(id: "m3", subject: "Compraste por $9.900 en un solo correo",
                             sender: "otras@davibank.com")
      })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      templates = result[:subject_templates]
      assert_equal [ { "value" => "Transacción aprobada por", "count" => 2,
                       "institution" => "DAVIbank" } ],
                   templates.map { |t| { "value" => t[:value], "count" => t[:count],
                                         "institution" => t[:institution] } }
      # A subject seen once is never a pattern.
      refute_includes templates.map { |t| t[:value] }, "Compraste por"
    end

    test "subjects without amounts stay whole when they recur" do
      FakeClient.configure(stubs: {
        "m1" => bank_message(id: "m1", subject: "Movimiento en tu cuenta Davibank en línea"),
        "m2" => bank_message(id: "m2", subject: "Movimiento en tu cuenta Davibank en línea"),
        "m3" => bank_message(id: "m3",
                             subject: "Consulta el detalle de tu nueva tarjeta haciendo clic para revisar hoy",
                             sender: "tercera@davibank.com")
      })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      templates =
        result[:subject_templates].filter_map do |t|
          { "value" => t[:value], "count" => t[:count] } if t[:value].start_with?("Movimiento")
        end
      assert_equal [ { "value" => "Movimiento en tu cuenta Davibank en línea", "count" => 2 } ], templates
    end

    test "suggested criteria come only from catalogued bank senders" do
      FakeClient.configure(stubs: {
        "m1" => bank_message(id: "m1", subject: "Transacción aprobada por $10.000 en A"),
        "m2" => bank_message(id: "m2", subject: "Transacción aprobada por $5.000 en B"),
        "m3" => {
          id: "m3", from: "Avisos Cuentas <avisos@micorreocuentas.com>",
          subject: "Transferencia aprobada: revisa tu cuenta",
          body_text: "Pagos, retiros y transferencias disponibles con tu tarjeta de crédito."
        },
        "m4" => {
          id: "m4", from: "Avisos Cuentas <avisos@micorreocuentas.com>",
          subject: "Transferencia aprobada: revisa tu cuenta",
          body_text: "Pagos, retiros y transferencias disponibles con tu tarjeta de crédito."
        }
      })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      # Not a catalogued bank: its sender/domain/subjects never become criteria
      # suggestions, no matter how many emails it sent.
      assert_equal [ { "value" => "notificaciones@davibank.com", "count" => 2 } ],
                   result[:senders].map { |s| { "value" => s[:value], "count" => s[:count] } }
      assert_equal [ { "value" => "davibank.com", "count" => 2 } ],
                   result[:domains].map { |d| { "value" => d[:value], "count" => d[:count] } }
      refute result[:subject_keywords].any? { |k| k[:value].in?([ "transferencia", "pagos" ]) }
      assert_equal [ { "value" => "Transacción aprobada por", "count" => 2,
                       "institution" => "DAVIbank" } ],
                   result[:subject_templates]
      # Money source discovery still only consumes bank-recognized messages.
      assert result[:suggestions].positive?
    end

    test "suggestions skip values already configured or confirmed" do
      @connection.update!(search_config: { senders: [ "notificaciones@davibank.com" ],
                                           domains: [], subject_keywords: [] })
      source = @user.money_sources.first
      recognition = source.create_recognition!
      recognition.recognition_identifiers.create!(
        [ { kind: "keyword", value: "transaccion" }, { kind: "subject", value: "Transacción Aprobada Por" } ]
          .map { |attrs| attrs.merge(status: "confirmed", origin: "user") }
      )

      FakeClient.configure(stubs: {
        "m1" => bank_message(id: "m1", subject: "Transacción aprobada por $50.000 en A"),
        "m2" => bank_message(id: "m2", subject: "Transacción aprobada por $10.000 en B")
      })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert_empty result[:senders]
      # The confirmed keyword blocks the catalog keyword, but different
      # catalog keywords found in the emails are still suggestions.
      refute result[:subject_keywords].any? { |k| k[:value].in?([ "transacción", "transaccion" ]) }
      # the confirmed subject template blocks the discovered template
      assert_empty result[:subject_templates]
      # Discovery suggestions are unaffected by the criteria dedup.
      assert result[:suggestions].positive?
    end

    test "one broken message never aborts the scan" do
      FakeClient.configure(stubs: { "m1" => bank_message }, fail_on: [ "m1" ])

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert_equal 1, result[:scanned]
      assert_equal 0, result[:passed]
      assert_empty result[:senders]
    end

    test "no imports happen during setup scan" do
      FakeClient.configure(stubs: { "m1" => bank_message })

      assert_no_difference "Expense.count" do
        assert_no_difference "ProcessedEmail.count" do
          SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))
        end
      end
    end

    test "inactive connection is a no-op" do
      @connection.update!(active: false)
      FakeClient.configure(stubs: { "m1" => bank_message })

      result = SetupScanService.call(@connection, client_class: FakeClient, logger: Logger.new(nil))

      assert result[:error].blank? || result[:scanned] == 0
      assert_nil @connection.reload.setup_suggestions
    end
  end
end

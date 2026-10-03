# frozen_string_literal: true

require "test_helper"

module Statements
  class ParserTest < ActiveSupport::TestCase
    FakeExtractor = Struct.new(:result) do
      def call(text:, today: Date.current)
        @called_with = text
        result
      end

      attr_reader :called_with
    end

    setup do
      @user = User.create!(name: "Parser User", email: "statements_parser@example.com", password: "password123")
      @extractor = FakeExtractor.new({ ok?: true, data: default_data, error: nil })
    end

    test "parses through the AI fallback and returns a canonical document" do
      result = Statements::Parser.call(user: @user, file_data: data_uri("fecha,valor\n2026-09-01,100"),
                                       filename: "extracto.csv", extractor: @extractor)

      assert result.success?
      document = result.result
      assert_equal :ai, document.engine
      assert_equal BigDecimal("1250300"), document.summary.total_due
      assert_equal BigDecimal("62515"), document.summary.min_payment
      assert_equal Date.new(2026, 9, 4), document.summary.due_date
      assert_equal "Restaurante XYZ", document.movements.first[:description]
      assert_equal "Visa", document.source.name
    end

    test "runs a matching layout adapter instead of the AI extractor" do
      adapter = Class.new do
        def self.matches?(_text)
          true
        end

        def self.call(_extraction)
          Statements::Document.new(engine: :adapter)
        end
      end

      stub_method(Statements::Adapters, :for, ->(_text) { adapter }) do
        result = Statements::Parser.call(user: @user, file_data: data_uri("a\n1"),
                                         filename: "extracto.csv", extractor: @extractor)

        assert result.success?
        assert_equal :adapter, result.result.engine
        assert_nil @extractor.called_with
      end
    end

    test "rejects a garbage payload" do
      result = Statements::Parser.call(user: @user, file_data: "data:text/csv;base64,!!!",
                                       filename: "extracto.csv", extractor: @extractor)
      assert_not result.success?
    end

    test "rejects an unsupported extension" do
      result = Statements::Parser.call(user: @user, file_data: data_uri("hello", "application/octet-stream"),
                                       filename: "extracto.txt", extractor: @extractor)
      assert_not result.success?
      assert_equal I18n.t("wizard.upload.unsupported_type"), result.errors.first
    end

    test "fails when no text can be extracted from the file" do
      result = Statements::Parser.call(user: @user, file_data: data_uri(""),
                                       filename: "extracto.csv", extractor: @extractor)
      assert_not result.success?
      assert_equal I18n.t("wizard.upload.extract_failed"), result.errors.first
    end

    test "propagates an AI extraction failure" do
      extractor = FakeExtractor.new({ ok?: false, data: nil, error: "AI extraction is not configured." })
      result = Statements::Parser.call(user: @user, file_data: data_uri("fecha,valor\n1,2"),
                                       filename: "extracto.csv", extractor: extractor)
      assert_not result.success?
      assert_equal "AI extraction is not configured.", result.errors.first
    end

    test "never creates records" do
      before = [ MoneySource.count, Transaction.count, ExpenseCandidate.count ]
      Statements::Parser.call(user: @user, file_data: data_uri("fecha,valor\n1,2"),
                              filename: "extracto.csv", extractor: @extractor)
      assert_equal before, [ MoneySource.count, Transaction.count, ExpenseCandidate.count ]
    end

    private

    def default_data
      { sources: [ { kind: "credit_card", name: "Visa", bank: "Davivienda",
                     card_last_four: "8976", balance: "2.180.000" } ],
        transactions: [ { date: "2026-08-23", description: "Restaurante XYZ",
                          amount: 48_500, type: "expense", category: "restaurants" } ],
        summary: { total_due: "1.250.300", min_payment: "62515", interest_charged: "45200",
                   due_date: "2026-09-04", statement_date: "2026-08-25" } }
    end

    def data_uri(content, mime = "text/csv")
      "data:#{mime};base64,#{Base64.strict_encode64(content)}"
    end
  end
end

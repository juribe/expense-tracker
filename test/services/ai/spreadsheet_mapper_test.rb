# frozen_string_literal: true

require "test_helper"

module Ai
  class SpreadsheetMapperTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Mapper User", email: "mapper@example.com", password: "password123")
      @headers = [ "Stamp", "Label", "Spent", "Brought", "Running" ]
      @rows = [ [ "2026-09-01", "DIDI FOOD", "45000", "", "1250000" ] ]
      @mapping = {
        "date_column" => "Stamp", "description_column" => "Label",
        "amount_column" => nil, "debit_column" => "Spent",
        "credit_column" => "Brought", "balance_column" => "Running"
      }
      @ai_payload = { mapping: @mapping, confidence: 0.97 }.to_json
    end

    test "unknown formats are mapped once by the strong model and persisted" do
      strong = FakeAiProvider.new(responses: [ @ai_payload ])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        result = Ai::SpreadsheetMapper.call(user: @user, headers: @headers, sample_rows: @rows)
      end

      assert result[:ok?]
      assert_equal @mapping, result[:mapping]
      assert_equal "strong_ai", result[:source]
      assert_equal 1, strong.calls.count

      stored = SpreadsheetFormatMapping.for_user(@user).find_by(fingerprint: SpreadsheetFormatMapping.fingerprint(@headers))
      assert_not_nil stored
      assert_equal @mapping, stored.mapping
      assert_equal "strong_ai", stored.source
      assert_in_delta 0.97, stored.confidence, 0.001
    end

    test "known formats reuse the stored mapping without any AI call" do
      SpreadsheetFormatMapping.record!(user: @user, headers: @headers, mapping: @mapping,
                                       source: "strong_ai", confidence: 0.97)
      strong = FakeAiProvider.new(responses: [])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        result = Ai::SpreadsheetMapper.call(user: @user, headers: @headers, sample_rows: @rows)
      end

      assert result[:ok?]
      assert_equal @mapping, result[:mapping]
      assert_equal "cache", result[:source]
      assert_equal 0, strong.calls.count
    end

    test "different header layouts produce different fingerprints" do
      assert_not_equal SpreadsheetFormatMapping.fingerprint([ "A", "B" ]),
                       SpreadsheetFormatMapping.fingerprint([ "A", "C" ])
    end

    test "fingerprints ignore header casing and accents" do
      assert_equal SpreadsheetFormatMapping.fingerprint([ "Fecha", "Descripción" ]),
                   SpreadsheetFormatMapping.fingerprint([ "fecha", "descripcion" ])
    end

    test "a user-confirmed mapping is not overwritten by a later AI result" do
      SpreadsheetFormatMapping.record!(user: @user, headers: @headers, mapping: @mapping, source: "user")

      strong = FakeAiProvider.new(responses: [ @ai_payload ])
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        Ai::SpreadsheetMapper.call(user: @user, headers: @headers, sample_rows: @rows)
      end

      assert_equal "user", SpreadsheetFormatMapping.for_user(@user).find_by!(fingerprint: SpreadsheetFormatMapping.fingerprint(@headers)).source
      assert_equal 0, strong.calls.count
    end

    test "when the strong model fails the error is recoverable" do
      strong = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("AI HTTP 500") ])

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        result = Ai::SpreadsheetMapper.call(user: @user, headers: @headers, sample_rows: @rows)
      end

      refute result[:ok?]
      assert_match(/AI HTTP 500/, result[:error])
      assert_nil SpreadsheetFormatMapping.for_user(@user).find_by(fingerprint: SpreadsheetFormatMapping.fingerprint(@headers))
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Gmail
  class CategoryPrefillTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Prefill User",
                           email: "prefill_#{SecureRandom.hex(6)}@example.com",
                           password: "password123")
      @mercado = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")
      @ocio = Category.create!(name: "Ocio y salidas", user: @user, is_default: false, category_type: "expense")
    end

    class FakeSuggester
      attr_reader :calls

      def initialize(data)
        @data = data
        @calls = []
      end

      def call(items)
        @calls << items
        Ai::Router::Result.new(ok?: true, data: @data, confidence: 0.9, strategy: "cheap_ai", error: nil)
      end
    end

    class FailingSuggester
      def call(_items)
        Ai::Router::Result.new(ok?: false, data: nil, confidence: nil, strategy: nil, error: "AI down")
      end
    end

    def transaction(overrides = {})
      {
        type: "expense",
        amount: BigDecimal("48500"),
        currency: "COP",
        merchant: "PRICESMART COLOMBIA",
        category: nil,
        occurred_at: "2026-10-27T14:30:00",
        confidence: 0.98,
        card_last_four: "1234",
        bank: "Davibank"
      }.merge(overrides)
    end

    def prefill(suggester)
      Gmail::CategoryPrefill.new(user: @user, suggester: suggester)
    end

    test "resolves an existing category without calling the suggester" do
      suggester = FakeSuggester.new({})

      result = prefill(suggester).call([ transaction(merchant: "SAO", category: "Mercado") ])

      assert_equal @mercado, result.first.category
      assert_nil result.first.suggestion
      assert_empty suggester.calls
    end

    test "sends one batched request for every unresolved transaction" do
      suggester = FakeSuggester.new({ "0" => "Mercado", "1" => "Ocio y salidas" })
      transactions = [
        transaction(merchant: "PRICESMART COLOMBIA"),
        transaction(merchant: "MULTIPLEX BUENAVISTA"),
        transaction(merchant: "SAO", category: "Mercado")
      ]

      result = prefill(suggester).call(transactions)

      assert_equal 1, suggester.calls.size
      assert_equal [
        { "index" => 0, "description" => "PRICESMART COLOMBIA" },
        { "index" => 1, "description" => "MULTIPLEX BUENAVISTA" }
      ], suggester.calls.first
      assert_equal @mercado, result[0].category
      assert_equal @ocio, result[1].category
      assert_equal @mercado, result[2].category
    end

    test "folds a free-form suggestion into an existing category" do
      restaurantes = Category.create!(name: "Restaurantes y cafés", user: @user,
                                      is_default: false, category_type: "expense")
      suggester = FakeSuggester.new({ "0" => "Restaurante" })

      result = prefill(suggester).call([ transaction(merchant: "SWEET BITES BY SAS") ])

      assert_equal restaurantes, result.first.category
      assert_nil result.first.suggestion
    end

    test "keeps the raw suggestion when no category matches" do
      suggester = FakeSuggester.new({ "0" => "Videojuegos" })

      assert_no_difference -> { Category.count } do
        result = prefill(suggester).call([ transaction(merchant: "STEAM GAMES") ])

        assert_nil result.first.category
        assert_equal "Videojuegos", result.first.suggestion
      end
    end

    test "does not request suggestions for non-expense entries" do
      suggester = FakeSuggester.new({})

      result = prefill(suggester).call([ transaction(type: "refund", merchant: "SAO") ])

      assert_empty suggester.calls
      assert_nil result.first.category
      assert_nil result.first.suggestion
    end

    test "skips the AI call when no provider is configured" do
      result = nil

      assert_no_difference -> { AiRequest.count } do
        result = Gmail::CategoryPrefill.new(user: @user).call([ transaction ])
      end

      assert_nil result.first.category
      assert_nil result.first.suggestion
    end

    test "keeps the category unresolved when the suggestion call fails" do
      result = prefill(FailingSuggester.new).call([ transaction ])

      assert_nil result.first.category
      assert_nil result.first.suggestion
    end
  end
end

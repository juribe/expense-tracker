# frozen_string_literal: true

require "test_helper"

module Statements
  module Adapters
    class AdaptersTest < ActiveSupport::TestCase
      FIXTURE = Rails.root.join("test/fixtures/files/davibank_credit_card.txt")

      setup do
        @user = User.create!(name: "Adapters", email: "adapters@example.com", password: "password123")
        @card = MoneySource.create!(user: @user, name: "Visa", kind: "credit_card", starting_balance: 0)
        @other = MoneySource.create!(user: @user, name: "Master", kind: "credit_card", starting_balance: 0)
        @text = File.read(FIXTURE)
      end

      test "returns a dynamic adapter when a learned layout matches the money source" do
        StatementFormatMapping.record!(
          user: @user,
          money_source: @card,
          anchors: [ "Davibank pertenece a Davivienda Group S.A.", "Transacciones del periodo facturado" ],
          sections: { "expenses" => [ "Transacciones del periodo facturado" ] },
          row: {
            "fields" => [
              { "token" => "date", "format" => "DD/MM/YYYY" },
              { "token" => "ref", "kind" => "digits", "length" => 6 },
              { "token" => "description", "optional" => true },
              { "token" => "amount", "currency" => "$" },
              { "token" => "ignore" }
            ]
          }
        )

        adapter = Adapters.for(@text, user: @user, money_source: @card)
        assert_kind_of DynamicAdapter, adapter
      end

      test "does not reuse a layout learned for another money source" do
        StatementFormatMapping.record!(
          user: @user,
          money_source: @card,
          anchors: [ "Davibank pertenece a Davivienda Group S.A.", "Transacciones del periodo facturado" ],
          sections: { "expenses" => [ "Transacciones del periodo facturado" ] },
          row: { "fields" => [ { "token" => "date", "format" => "DD/MM/YYYY" }, { "token" => "amount", "currency" => "$" } ] }
        )

        assert_nil Adapters.for(@text, user: @user, money_source: @other)
      end

      test "returns nil when no learned layout matches" do
        assert_nil Adapters.for(@text, user: @user, money_source: @card)
      end

      test "returns nil without a user" do
        assert_nil Adapters.for(@text)
      end

      test "returns nil without a money source" do
        assert_nil Adapters.for(@text, user: @user, money_source: nil)
      end

      test "returns nil when the learned recipe does not compile" do
        StatementFormatMapping.record!(
          user: @user, money_source: @card,
          anchors: [ "Davibank pertenece a Davivienda Group S.A." ],
          sections: { "expenses" => [ "Transacciones del periodo facturado" ] },
          row: { "fields" => [ { "token" => "description" } ] }
        )

        assert_nil Adapters.for(@text, user: @user, money_source: @card)
      end
    end
  end
end

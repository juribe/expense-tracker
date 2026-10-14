# frozen_string_literal: true

require "test_helper"

module Statements
  module Adapters
    class AdaptersTest < ActiveSupport::TestCase
      FIXTURE = Rails.root.join("test/fixtures/files/davibank_credit_card.txt")

      setup do
        @user = User.create!(name: "Adapters", email: "adapters@example.com", password: "password123")
        @text = File.read(FIXTURE)
      end

      test "returns a dynamic adapter when a learned layout matches" do
        StatementFormatMapping.record!(
          user: @user,
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

        adapter = Adapters.for(@text, user: @user)

        assert_instance_of DynamicAdapter, adapter
      end

      test "returns nil without a matching learned layout" do
        assert_nil Adapters.for(@text, user: @user)
      end

      test "returns nil without a user" do
        assert_nil Adapters.for(@text)
      end

      test "ignores a learned layout that cannot be compiled" do
        StatementFormatMapping.record!(
          user: @user,
          anchors: [ "Davibank pertenece a Davivienda Group S.A." ],
          sections: { "expenses" => [ "Transacciones del periodo facturado" ] },
          row: { "fields" => [ { "token" => "description" } ] }
        )

        assert_nil Adapters.for(@text, user: @user)
      end
    end
  end
end

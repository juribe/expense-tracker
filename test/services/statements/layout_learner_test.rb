# frozen_string_literal: true

require "test_helper"

module Statements
  class LayoutLearnerTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/davibank_credit_card.txt")

    setup do
      @user = User.create!(name: "Layout Learner", email: "layout_learner@example.com", password: "password123")
      @text = File.read(FIXTURE)
      @layout = {
        "bank" => "Davibank",
        "anchors" => [ "Davibank pertenece a Davivienda Group S.A.", "Transacciones del periodo facturado" ],
        "sections" => { "expenses" => [ "Transacciones del periodo facturado", "Transacciones de periodos anteriores" ] },
        "row" => {
          "fields" => [
            { "token" => "date", "format" => "DD/MM/YYYY" },
            { "token" => "ref", "kind" => "digits", "length" => 6 },
            { "token" => "description", "optional" => true },
            { "token" => "amount", "currency" => "$" },
            { "token" => "ignore" }
          ],
          "cancelled_pattern" => "CANCELADA"
        },
        "summary" => {
          "total_due" => { "label" => "= Pago total" },
          "interest_charged" => { "label" => "+ Intereses corrientes" },
          "due_date" => { "label" => "Fecha de pago" }
        },
        "confidence" => 0.95
      }
    end

    test "persists a valid layout and returns the mapping" do
      mapping = LayoutLearner.call(user: @user, text: @text, layout: @layout)

      assert_not_nil mapping
      assert mapping.persisted?
      assert_equal @user.id, mapping.user_id
      assert_equal "Davibank", mapping.bank
      assert_equal [ "Davibank pertenece a Davivienda Group S.A.", "Transacciones del periodo facturado" ], mapping.anchors
    end

    test "persists the summary selectors that resolve against the text" do
      mapping = LayoutLearner.call(user: @user, text: @text, layout: @layout)

      assert_equal %w[total_due interest_charged due_date], mapping.summary_spec.keys
      summary = Adapters::DynamicAdapter.new(mapping)
                                      .call(Expenses::FileImport::Readers::Extraction.new(text: @text)).summary
      assert_equal BigDecimal("3983689"), summary.total_due
      assert_equal Date.new(2026, 10, 7), summary.due_date
    end

    test "drops summary selectors whose label is not printed" do
      layout = @layout.merge("summary" => {
        "total_due" => { "label" => "= Pago total" },
        "min_payment" => { "label" => "No existe" }
      })

      mapping = LayoutLearner.call(user: @user, text: @text, layout: layout)

      assert_equal %w[total_due], mapping.summary_spec.keys
    end

    test "does not persist a layout whose anchors are missing from the text" do
      layout = @layout.merge("anchors" => [ "Bancolombia" ])

      assert_nil LayoutLearner.call(user: @user, text: @text, layout: layout)
      assert_equal 0, StatementFormatMapping.for_user(@user).count
    end

    test "does not persist a layout whose pattern matches too few rows" do
      layout = @layout.merge("sections" => { "expenses" => [ "Transacciones del periodo facturado" ] },
                             "row" => @layout["row"].merge("cancelled_pattern" => nil))
      text = "Davibank pertenece a Davivienda Group S.A.\nTransacciones del periodo facturado\n" \
             "    18/09/2026       734987                                    $ 24.000        1/1\n"

      assert_nil LayoutLearner.call(user: @user, text: text, layout: layout)
    end

    test "does not persist a layout below the confidence threshold" do
      layout = @layout.merge("confidence" => 0.4)

      assert_nil LayoutLearner.call(user: @user, text: @text, layout: layout)
    end

    test "does not persist a layout with an uncompilable row spec" do
      layout = @layout.merge("row" => { "fields" => [ { "token" => "description" } ] })

      assert_nil LayoutLearner.call(user: @user, text: @text, layout: layout)
    end

    test "returns nil for a blank layout" do
      assert_nil LayoutLearner.call(user: @user, text: @text, layout: nil)
      assert_nil LayoutLearner.call(user: @user, text: @text, layout: {})
    end
  end
end

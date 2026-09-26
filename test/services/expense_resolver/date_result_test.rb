require "test_helper"

module ExpenseResolver
  class DateResultTest < ActiveSupport::TestCase
    test "a range expression in the message overrides a model-invented fragment date" do
      entry = Ai::Tasks::ParsedExpense.new(
        original_text: "hoy gasté 150.000 en ropa", amount: 150_000,
        date: Date.current.iso8601, description: "ropa", category: nil,
        money_source_hint: nil, confidence: 0.9
      )

      result = DateResult.call(
        expense: entry,
        full_text: "El viernes gasté 150.000 en ropa con la tarjeta Davibank",
        entry_position: 0, entry_count: 1
      )

      expected = Date.current.days_ago(((Date.current.wday - 5) % 7).zero? ? 7 : (Date.current.wday - 5) % 7)
      assert_equal expected, result.date
    end

    test "a weekday invented by the model but absent from the message is ignored" do
      entry = Ai::Tasks::ParsedExpense.new(
        original_text: "pagué 80.000 de supermercado con Davibank", amount: 80_000,
        date: Date.current.iso8601, description: "supermercado", category: nil,
        money_source_hint: nil, confidence: 0.9
      )

      result = DateResult.call(
        expense: entry,
        full_text: "pagué 80.000 de supermercado con Davibank",
        entry_position: 0, entry_count: 1
      )

      assert_equal Date.current, result.date
    end

    test "a fragment's single date expression outranks the model date in multi-entry messages" do
      entry = Ai::Tasks::ParsedExpense.new(
        original_text: "El viernes gasté 150.000 en ropa", amount: 150_000,
        date: (Date.current - 2).iso8601, description: "ropa", category: nil,
        money_source_hint: nil, confidence: 0.9
      )

      result = DateResult.call(
        expense: entry, allow_heuristic: false,
        full_text: "El viernes gasté 150.000 en ropa, 80.000 en comida y 20.000 en taxi en efectivo",
        entry_position: 0, entry_count: 3
      )

      friday = Date.current
      friday -= 1 until friday.wday == 5 && friday < Date.current
      assert_equal friday, result.date
    end
  end
end

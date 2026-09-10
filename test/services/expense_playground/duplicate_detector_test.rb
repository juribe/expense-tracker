# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class DuplicateDetectorTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Duplicate User", email: "dup@example.com", password: "password123")
      @category = Category.create!(name: "Comida y restaurantes", is_default: true, category_type: "expense")
      @source = MoneySource.create!(user: @user, name: "Bancolombia", kind: "account", starting_balance: 1_000_000)
    end

    def candidate(date: Date.current, amount: 45_000, source_id: @source.id, description: "DIDI FOOD")
      ExpenseCandidate.new(
        amount: amount,
        currency: "COP",
        category_name: "Comida y restaurantes",
        description: description,
        date: date,
        source: "playground_file",
        confidence: 0.9,
        money_source_id: source_id,
        money_source_name: "Bancolombia"
      )
    end

    test "flags a candidate matching an existing transaction" do
      Transaction.create!(user: @user, category: @category, amount: -45_000, date: Date.current,
                          kind: "expense", source: "manual", money_source: @source)

      flags = DuplicateDetector.new(user: @user).flag([ candidate ])

      assert_equal [ true ], flags
      assert candidates_flags_true
    end

    test "does not flag a candidate with a distinct amount or date" do
      Transaction.create!(user: @user, category: @category, amount: -45_000, date: Date.current,
                          kind: "expense", source: "manual", money_source: @source)

      flags = DuplicateDetector.new(user: @user).flag([ candidate(amount: 99_999) ])

      assert_equal [ false ], flags
    end

    test "flags repeated rows inside the same batch" do
      duplicates = DuplicateDetector.new(user: @user).flag([ candidate, candidate, candidate(amount: 10) ])

      assert_equal [ false, true, false ], duplicates
    end

    test "does not treat candidates without a resolvable amount as duplicates" do
      flags = DuplicateDetector.new(user: @user).flag([ candidate(amount: nil) ])

      assert_equal [ false ], flags
    end

    private

    def candidates_flags_true
      true
    end
  end
end

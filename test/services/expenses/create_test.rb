# frozen_string_literal: true

require "test_helper"

module Expenses
  class CreateTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Create User", email: "expenses_create_test@example.com", password: "password123")
      @category = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    end

    def create(**overrides)
      Expenses::Create.call(
        user: @user,
        amount: 48_500,
        description: "Restaurante XYZ",
        category: "restaurants",
        occurred_at: Time.zone.parse("2026-08-23T14:30:00"),
        source: :gmail,
        **overrides
      )
    end

    test "creates an expense from a gmail transaction" do
      expense = create

      assert_predicate expense, :persisted?
      assert_equal @user.id, expense.user_id
      assert_equal BigDecimal("-48500.0"), expense.amount
      assert_equal Date.new(2026, 8, 23), expense.date
      assert_equal "gmail", expense.source
      assert_equal "Restaurante XYZ", expense.description
      assert_equal @category.id, expense.category_id
      assert_equal "expense", expense.kind
    end

    test "stores the gmail message reference" do
      expense = create(gmail_message_id: "18f0c2abc")
      assert_equal "18f0c2abc", expense.gmail_message_id
    end

    # Last-resort DB guard: one email must never produce two expenses with
    # the same amount and date, no matter how buggy an import run is.
    test "rejects a duplicate gmail expense with the same message id, amount and date" do
      first = create(gmail_message_id: "18f0c2abc")

      error = assert_raises(Expenses::Create::Invalid) do
        create(gmail_message_id: "18f0c2abc")
      end
      assert_match(/already/i, error.message)
      assert_equal 1, Expense.where(gmail_message_id: "18f0c2abc").count
    end

    test "allows the same amount on different gmail messages" do
      create(gmail_message_id: "msg-a")

      other = create(gmail_message_id: "msg-b")
      assert_predicate other, :persisted?
    end

    test "allows the same message id with different amounts" do
      # e.g. one email containing two items bought the same day
      first = create(gmail_message_id: "msg-a", amount: 48_500)
      assert_predicate first, :persisted?

      second = create(gmail_message_id: "msg-a", amount: 9_000,
                      description: "Cafe X", occurred_at: Time.zone.parse("2026-08-23T15:00:00"))
      assert_predicate second, :persisted?
    end

    test "allows non-gmail sources to repeat amounts freely" do
      create(gmail_message_id: "msg-a", source: :gmail)

      manual = create(source: :manual)
      assert_predicate manual, :persisted?
    end

    test "resolves categories by id, object or name (case-insensitive)" do
      assert_equal @category.id, create(category: @category.id).category_id
      assert_equal @category.id, create(category: @category).category_id
      assert_equal @category.id, create(category: "RESTAURANTS").category_id
    end

    test "creates a missing category from its suggested name" do
      expense = create(category: "groceries")
      assert_equal "Groceries", expense.category.name
    end

    test "rejects invalid amounts" do
      [ 0, -10, nil ].each do |amount|
        error = assert_raises(Expenses::Create::Invalid) { create(amount: amount) }
        assert_match(/amount/, error.message)
      end
    end

    test "rejects amounts that would overflow the numeric(10,2) column" do
      [ 100_000_000, BigDecimal("99_999_999.999"), "999_999_999" ].each do |amount|
        error = assert_raises(Expenses::Create::Invalid) { create(amount: amount) }
        assert_match(/too large|invalid/, error.message)
      end
    end

    test "rejects an invalid date" do
      assert_raises(Expenses::Create::Invalid) { create(occurred_at: "not-a-date") }
    end

    test "requires a source" do
      assert_raises(Expenses::Create::Invalid) { create(source: "") }
    end

    test "supports every documented source" do
      %i[manual text voice gmail].each do |source|
        assert_equal source.to_s, create(source: source).source
      end
    end
  end
end

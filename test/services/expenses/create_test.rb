# frozen_string_literal: true

require "test_helper"

module Expenses
  class CreateTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Create User", email: "expenses_create_test@example.com", password: "password123")
      @category = Category.create!(name: "Restaurants")
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

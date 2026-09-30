# frozen_string_literal: true

require "test_helper"

module Expenses
  class BulkCreateTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "BC User", email: "bulk_create@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @account = MoneySource.create!(user: @user, name: "Cuenta", kind: "account")
    end

    test "creates one expense per confirmed input inside a transaction" do
      result = BulkCreate.call(user: @user, inputs: [ confirmed_input, confirmed_input(description: "Cena") ])

      assert result.success?
      assert_equal 2, result.created_count
      assert_equal 2, @user.expenses.count
      assert_equal "ai", @user.expenses.first.source
      assert_equal BigDecimal("-50000"), @user.expenses.first.amount
    end

    test "attaches the money source when provided" do
      result = BulkCreate.call(user: @user, inputs: [ confirmed_input(money_source_id: @account.id) ])

      assert result.success?
      assert_equal @account.id, @user.expenses.first.money_source_id
    end

    test "marks category as locked by the user when the input was edited" do
      result = BulkCreate.call(user: @user, inputs: [ confirmed_input(category_edited: "1") ])

      assert result.success?
      assert result.expenses.first.category_locked_by_user
    end

    test "returns the created expenses in order" do
      result = BulkCreate.call(user: @user, inputs: [ confirmed_input, confirmed_input(description: "Cena") ])

      assert_equal [ "Almuerzo", "Cena" ], result.expenses.map(&:description)
    end

    test "accepts raw params objects and skips blanks" do
      nested = ActionController::Parameters.new(
        "0" => { "amount" => "50000", "description" => "Almuerzo", "transaction_date" => Date.current.iso8601,
                 "category_id" => @category.id.to_s },
        "1" => ""
      )

      result = BulkCreate.call(user: @user, inputs: nested)

      assert result.success?
      assert_equal 1, result.created_count
    end

    test "fails the whole batch and rolls back on invalid amount" do
      result = BulkCreate.call(user: @user, inputs: [
                                 confirmed_input,
                                 confirmed_input(amount: "0")
                               ])

      assert result.failure?
      assert_match(/2/, result.error_message)
      assert_equal 0, @user.expenses.count
    end

    test "fails with a localized message when no expenses are given" do
      result = BulkCreate.call(user: @user, inputs: [])

      assert result.failure?
      assert_match(/gastos/i, result.error_message)
      assert_equal 0, @user.expenses.count
    end

    test "invalid dates fail the batch" do
      result = BulkCreate.call(user: @user, inputs: [ confirmed_input(transaction_date: nil, date: "31/02/2026") ])

      assert result.failure?
      assert_match(/fecha/i, result.error_message)
      assert_equal 0, @user.expenses.count
    end

    test "creates a brand new category when a close match does not exist" do
      inputs = [ confirmed_input(category_id: nil, new_category_name: "Mascotas") ]

      result = BulkCreate.call(user: @user, inputs: inputs)

      assert result.success?
      assert_equal "Mascotas", @user.expenses.first.category.name
    end

    def confirmed_input(overrides = {})
      {
        amount: "50000",
        description: "Almuerzo",
        date: Date.current.iso8601,
        transaction_date: Date.current.iso8601,
        category_id: @category.id,
        new_category_name: nil,
        category_edited: nil,
        confidence: "0.9",
        money_source_id: nil
      }.merge(overrides)
    end
  end
end

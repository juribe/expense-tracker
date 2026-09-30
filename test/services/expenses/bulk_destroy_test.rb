# frozen_string_literal: true

require "test_helper"

module Expenses
  class BulkDestroyTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "BD User", email: "bulk_destroy@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @expense_a = create_expense(description: "A")
      @expense_b = create_expense(description: "B")
    end

    test "destroys only the selected ids of the current user" do
      result = BulkDestroy.call(user: @user, ids: [@expense_a.id, @expense_b.id])

      assert result.success?
      assert_equal 2, result.deleted_count
      assert_not Expense.exists?(@expense_a.id)
      assert_not Expense.exists?(@expense_b.id)
    end

    test "never touches another user's expense even if its id is passed" do
      other = User.create!(name: "Otto", email: "other_bd@example.com", password: "password123")
      foreign = Expense.create!(
        user: other, category: @category, amount: 500, description: "Ajeno",
        date: Date.current, source: "manual"
      )

      result = BulkDestroy.call(user: @user, ids: [foreign.id])

      # A foreign-only id list matches nothing for this user, so the service
      # reports no_selection exactly like the controller used to.
      assert result.failure?
      assert_equal 0, result.deleted_count
      assert Expense.exists?(foreign.id)
    end

    test "ignores blanks, commas and zero values in the raw id list" do
      result = BulkDestroy.call(user: @user, ids: ["", "0", @expense_a.id.to_s, nil])

      assert result.success?
      assert_equal 1, result.deleted_count
    end

    test "returns no_selection failure when nothing matches" do
      result = BulkDestroy.call(user: @user, ids: [])

      assert result.failure?
      assert_equal 0, result.deleted_count
    end

    # Minitest has no instance stubbing; prepend a guard that only blocks a
    # uniquely named record. Inert everywhere else in the suite.
    RECORD_GUARD = Module.new do
      def destroy!
        raise ActiveRecord::RecordNotDestroyed, "locked" if description == "BulkDestroyTest::UNDESTROYABLE"

        super
      end
    end

    test "tallies partial failures when a record cannot be destroyed" do
      Expense.prepend(RECORD_GUARD) unless Expense.ancestors.include?(RECORD_GUARD)
      expense = create_expense(description: "BulkDestroyTest::UNDESTROYABLE")

      result = BulkDestroy.call(user: @user, ids: [expense.id, @expense_a.id])

      assert_equal 1, result.deleted_count
      assert_equal 1, result.failed_count
      assert Expense.exists?(expense.id)
    end

    def create_expense(**overrides)
      Expense.create!(
        {
          user: @user, category: @category, amount: 10_000, description: "Gasto",
          date: Date.current, source: "manual"
        }.merge(overrides)
      )
    end
  end
end

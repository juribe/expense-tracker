# frozen_string_literal: true

require "test_helper"

module Expenses
  class BulkUpdateTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "BU User", email: "bulk_update@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @new_category = Category.create!(name: "Transporte", user: @user, is_default: false, category_type: "expense")
      @foreign_category = Category.create!(name: "Ajena", is_default: false, category_type: "expense")
      @account = MoneySource.create!(user: @user, name: "Cuenta", kind: "account")
      @card = MoneySource.create!(user: @user, name: "Tarjeta", kind: "credit_card")
      @expense_a = create_expense
      @expense_b = create_expense
    end

    test "updates category and money source of selected expenses" do
      result = BulkUpdate.call(
        user: @user, ids: [@expense_a.id, @expense_b.id],
        category_id: @new_category.id, money_source_id: @card.id
      )

      assert result.success?
      assert_equal 2, result.updated_count
      assert_equal @new_category.id, @expense_a.reload.category_id
      assert_equal @card.id, @expense_a.reload.money_source_id
    end

    test "updates only category when money source is nil" do
      result = BulkUpdate.call(user: @user, ids: [@expense_a.id], category_id: @new_category.id, money_source_id: nil)

      assert result.success?
      assert_equal @new_category.id, @expense_a.reload.category_id
      # A nil money source means "no change", not "clear the source".
      assert_equal @account.id, @expense_a.reload.money_source_id
    end

    test "fails with no_selection when ids are empty" do
      result = BulkUpdate.call(user: @user, ids: [], category_id: @new_category.id)

      assert result.failure?
      assert_equal :no_selection, result.error_key
    end

    test "fails when neither category nor money source given" do
      result = BulkUpdate.call(user: @user, ids: [@expense_a.id], category_id: nil, money_source_id: nil)

      assert result.failure?
      assert_equal :nothing_to_change, result.error_key
    end

    test "fails when category belongs to another user" do
      result = BulkUpdate.call(user: @user, ids: [@expense_a.id], category_id: @foreign_category.id)

      assert result.failure?
      assert_equal :category_not_found, result.error_key
    end

    test "fails when money source belongs to another user" do
      other = User.create!(name: "Otro BU", email: "other_bu@example.com", password: "password123")
      foreign_source = MoneySource.create!(user: other, name: "Ajena", kind: "account")

      result = BulkUpdate.call(user: @user, ids: [@expense_a.id], category_id: nil, money_source_id: foreign_source.id)

      assert result.failure?
      assert_equal :source_not_found, result.error_key
    end

    test "fails when nothing matches the ids" do
      result = BulkUpdate.call(user: @user, ids: [999_999], category_id: @new_category.id)

      assert result.failure?
      assert_equal :no_selection, result.error_key
    end

    def create_expense
      Expense.create!(
        user: @user, category: @category, amount: 10_000, description: "Gasto",
        date: Date.current, source: "manual", money_source: @account
      )
    end
  end
end

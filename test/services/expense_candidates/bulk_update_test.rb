# frozen_string_literal: true

require "test_helper"

module ExpenseCandidates
  class BulkUpdateTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "CBU User", email: "cand_bulk_update@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @new_category = Category.create!(name: "Transporte", user: @user, is_default: false, category_type: "expense")
      @source = MoneySource.create!(user: @user, name: "Davibank Ctrl", kind: "debit_card")
      @card = MoneySource.create!(user: @user, name: "Crédito Vehículo", kind: "credit_card")
      @candidate_a = create_candidate
      @candidate_b = create_candidate
    end

    test "updates category and money source of selected candidates" do
      result = BulkUpdate.call(
        user: @user, ids: [@candidate_a.id, @candidate_b.id],
        category_id: @new_category.id, money_source_id: @card.id
      )

      assert result.success?
      assert_equal 2, result.updated_count
      assert_equal @new_category.id, @candidate_a.reload.category_id
      assert_equal @card.id, @candidate_b.reload.money_source_id
    end

    test "fails with no_selection when ids are empty" do
      result = BulkUpdate.call(user: @user, ids: [], category_id: @new_category.id)

      assert result.failure?
      assert_equal :no_selection, result.error_key
    end

    test "fails when neither category nor source given" do
      result = BulkUpdate.call(user: @user, ids: [@candidate_a.id], category_id: nil, money_source_id: nil)

      assert result.failure?
      assert_equal :nothing_to_change, result.error_key
    end

    test "fails when category is not one of the user's expense categories" do
      other = User.create!(name: "Otro CBU", email: "other_cbu@example.com", password: "password123")
      foreign = Category.create!(name: "Ajena", user: other, is_default: false, category_type: "expense")

      result = BulkUpdate.call(user: @user, ids: [@candidate_a.id], category_id: foreign.id)

      assert result.failure?
      assert_equal :category_not_found, result.error_key
    end

    test "fails when money source is not a payment origin" do
      other = User.create!(name: "Otro CBU2", email: "other_cbu2@example.com", password: "password123")
      foreign_source = MoneySource.create!(user: other, name: "Ajena", kind: "account")

      result = BulkUpdate.call(user: @user, ids: [@candidate_a.id], category_id: nil, money_source_id: foreign_source.id)

      assert result.failure?
      assert_equal :source_not_found, result.error_key
    end

    test "fails when nothing matches the ids" do
      result = BulkUpdate.call(user: @user, ids: [999_999], category_id: @new_category.id)

      assert result.failure?
      assert_equal :no_selection, result.error_key
    end

    def create_candidate
      ExpenseCandidate.create!(
        user: @user, amount: 50_000, date: Date.current,
        source: "text", status: "needs_review"
      )
    end
  end
end

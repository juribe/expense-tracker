# frozen_string_literal: true

require "test_helper"

module ExpenseCandidates
  class BulkConfirmTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "CBC User", email: "cand_bulk_confirm@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @source = MoneySource.create!(user: @user, name: "Davibank Ctrl", kind: "debit_card")
      @candidate = create_candidate(category: @category, money_source: @source, description: "Almuerzo")
      @incomplete = create_candidate
    end

    test "confirms ready candidates into expenses" do
      result = BulkConfirm.call(user: @user, ids: [@candidate.id])

      assert result.success?
      assert_equal 1, result.confirmed_count
      assert_equal 0, result.errors.length
      assert @candidate.reload.confirmed?
      assert_not_nil @candidate.reload.expense_id
    end

    test "reports per-candidate errors for incomplete candidates" do
      result = BulkConfirm.call(user: @user, ids: [@candidate.id, @incomplete.id])

      assert result.success?
      assert_equal 1, result.confirmed_count
      assert_equal 1, result.errors.length
      assert_equal @incomplete.id, result.errors.first[:id]
      assert_match(/money_source_id|fuente/i, result.errors.first[:errors].join(", "))
    end

    test "fails with no_selection when ids are empty" do
      result = BulkConfirm.call(user: @user, ids: [])

      assert result.failure?
      assert_equal :no_selection, result.error_key
      assert_equal 0, result.confirmed_count
    end

    test "fails when category or source do not belong to the user" do
      other = User.create!(name: "Otro CBC", email: "other_cbc@example.com", password: "password123")
      foreign_category = Category.create!(name: "Ajena", user: other, is_default: false, category_type: "expense")

      result = BulkConfirm.call(user: @user, ids: [@candidate.id], category_id: foreign_category.id)

      assert result.failure?
      assert_equal :category_not_found, result.error_key
    end

    def create_candidate(**overrides)
      ExpenseCandidate.create!(
        {
          user: @user, amount: 50_000, date: Date.current,
          description: "Candidato", source: "text", status: "needs_review"
        }.merge(overrides)
      )
    end
  end
end

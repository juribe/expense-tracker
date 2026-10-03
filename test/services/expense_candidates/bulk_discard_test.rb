# frozen_string_literal: true

require "test_helper"

module ExpenseCandidates
  class BulkDiscardTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "CBD User", email: "cand_bulk_discard@example.com", password: "password123")
      @candidate_a = create_candidate
      @candidate_b = create_candidate
    end

    test "discards the selected candidates and sets discarded_at" do
      result = BulkDiscard.call(user: @user, ids: [@candidate_a.id, @candidate_b.id])

      assert result.success?
      assert_equal 2, result.discarded_count
      assert_equal "discarded", @candidate_a.reload.status
      assert_equal "discarded", @candidate_b.reload.status
      assert_not_nil @candidate_a.discarded_at
    end

    test "ignores blanks, commas and zero values in the raw id list" do
      result = BulkDiscard.call(user: @user, ids: ["", "0", @candidate_a.id.to_s, nil])

      assert result.success?
      assert_equal 1, result.discarded_count
    end

    test "fails with no_selection when ids are empty" do
      result = BulkDiscard.call(user: @user, ids: [])

      assert result.failure?
      assert_equal :no_selection, result.error_key
      assert_equal 0, result.discarded_count
    end

    test "fails with no_selection when nothing matches the ids" do
      result = BulkDiscard.call(user: @user, ids: [999_999])

      assert result.failure?
      assert_equal :no_selection, result.error_key
    end

    test "never touches another user's candidate even if its id is passed" do
      other = User.create!(name: "Otro CBD", email: "other_cbd@example.com", password: "password123")
      foreign = ExpenseCandidate.create!(user: other, amount: 100, date: Date.current, source: "text", status: "needs_review")

      result = BulkDiscard.call(user: @user, ids: [foreign.id])

      assert result.failure?
      assert_equal :no_selection, result.error_key
      assert_equal 0, result.discarded_count
      assert_equal "needs_review", foreign.reload.status
    end

    test "keeps already confirmed candidates confirmed and does not count them" do
      category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      source = MoneySource.create!(user: @user, name: "Davibank", kind: "debit_card")
      confirmed = create_candidate(status: "ready", category_id: category.id, money_source_id: source.id, description: "Conf")
      confirmed.confirm!

      result = BulkDiscard.call(user: @user, ids: [confirmed.id, @candidate_a.id])

      assert result.success?
      assert_equal 1, result.discarded_count
      assert_equal "confirmed", confirmed.reload.status
      assert_equal "discarded", @candidate_a.reload.status
    end

    def create_candidate(**overrides)
      ExpenseCandidate.create!(
        { user: @user, amount: 50_000, date: Date.current,
          source: "text", status: "needs_review" }.merge(overrides)
      )
    end
  end
end

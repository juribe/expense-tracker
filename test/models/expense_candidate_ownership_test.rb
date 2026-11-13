# frozen_string_literal: true

require "test_helper"

class ExpenseCandidateOwnershipTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Candidate Owner", email: "candidate_owner@example.com", password: "password123")
    @other = User.create!(name: "Other Owner", email: "candidate_other@example.com", password: "password123")
    @shared_category = Category.create!(name: "Compartida", is_default: true, category_type: "expense")
    @foreign_category = Category.create!(name: "Ajena", user: @other, is_default: false, category_type: "expense")
    @foreign_source = @other.money_sources.create!(name: "Ajena", kind: "cash", starting_balance: 1_000)
  end

  test "rejects another user's category and money source" do
    candidate = build_candidate(category: @foreign_category, money_source: @foreign_source)

    refute candidate.valid?
    assert candidate.errors[:category].any?
    assert candidate.errors[:money_source].any?
  end

  test "accepts shared default categories" do
    assert build_candidate(category: @shared_category).valid?
  end

  private

  def build_candidate(**attrs)
    ExpenseCandidate.new(
      user: @user, amount: 1_000, date: Date.current, source: "text", **attrs
    )
  end
end

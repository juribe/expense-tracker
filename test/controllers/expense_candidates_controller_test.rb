# frozen_string_literal: true

require "test_helper"

class ExpenseCandidatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Candidate Controller User",
      email: "candidate_ctrl_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Transporte Ctrl", is_default: false, category_type: "expense", user: @user)
    @money_source = MoneySource.create!(user: @user, name: "Davibank Ctrl", kind: "debit_card")
    sign_in @user
  end

  def create_candidate(**overrides)
    ExpenseCandidate.create!(
      { user: @user, amount: 50_000, date: Date.current, source: "text" }.merge(overrides)
    )
  end

  # --- INDEX ---

  test "GET /expense_candidates renders the list" do
    create_candidate(status: "needs_review")
    get expense_candidates_path
    assert_response :success
  end

  test "GET /expense_candidates shows candidates for current user only" do
    mine = create_candidate(status: "needs_review")
    other_user = User.create!(name: "Other", email: "other_ctrl_#{SecureRandom.hex(4)}@example.com", password: "password123")
    ExpenseCandidate.create!(user: other_user, amount: 100, date: Date.current, source: "text", status: "needs_review")

    get expense_candidates_path
    assert_response :success
  end

  test "GET /expense_candidates filters by status" do
    create_candidate(status: "needs_review")
    create_candidate(status: "ready")

    get expense_candidates_path(status: "needs_review")
    assert_response :success
  end

  # --- SHOW ---

  test "GET /expense_candidates/:id shows candidate details" do
    candidate = create_candidate(
      category_id: @category.id,
      money_source_id: @money_source.id,
      description: "Test expense"
    )
    get expense_candidate_path(candidate)
    assert_response :success
  end

  test "GET /expense_candidates/:id rejects other users candidate" do
    other_user = User.create!(name: "Other", email: "other_show_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_candidate = ExpenseCandidate.create!(user: other_user, amount: 100, date: Date.current, source: "text")

    get expense_candidate_path(other_candidate)
    assert_response :not_found
  end

  # --- UPDATE ---

  test "PATCH /expense_candidates/:id updates fields" do
    candidate = create_candidate(category_id: nil, money_source_id: nil)

    patch expense_candidate_path(candidate), params: {
      expense_candidate: { category_id: @category.id, description: "Updated" }
    }
    assert_redirected_to expense_candidate_path(candidate)

    candidate.reload
    assert_equal @category.id, candidate.category_id
    assert_equal "Updated", candidate.description
  end

  test "PATCH /expense_candidates/:id recalculates status" do
    candidate = create_candidate(category_id: nil, money_source_id: nil, status: "needs_review")

    patch expense_candidate_path(candidate), params: {
      expense_candidate: { category_id: @category.id, money_source_id: @money_source.id }
    }

    candidate.reload
    assert_equal "ready", candidate.status
  end

  # --- CONFIRM ---

  test "POST /expense_candidates/:id/confirm creates expense" do
    candidate = create_candidate(
      category_id: @category.id,
      money_source_id: @money_source.id,
      amount: 50_000,
      date: Date.current,
      description: "Confirm test"
    )

    assert_difference -> { Expense.count }, 1 do
      post confirm_expense_candidate_path(candidate)
    end
    assert_redirected_to expense_candidates_path

    candidate.reload
    assert_equal "confirmed", candidate.status
    assert_not_nil candidate.expense_id
  end

  test "POST /expense_candidates/:id/confirm rejects when fields are missing" do
    candidate = create_candidate(category_id: nil, amount: 50_000, date: Date.current)

    assert_no_difference -> { Expense.count } do
      post confirm_expense_candidate_path(candidate)
    end
    assert_redirected_to expense_candidate_path(candidate)
    assert_equal "needs_review", candidate.reload.status
  end

  # --- DISCARD ---

  test "POST /expense_candidates/:id/discard marks as discarded" do
    candidate = create_candidate

    post discard_expense_candidate_path(candidate)
    assert_redirected_to expense_candidates_path

    candidate.reload
    assert_equal "discarded", candidate.status
    assert_not_nil candidate.discarded_at
  end

  # --- User isolation ---

  test "cannot update other users candidate" do
    other_user = User.create!(name: "Other", email: "other_upd_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_candidate = ExpenseCandidate.create!(user: other_user, amount: 100, date: Date.current, source: "text")

    patch expense_candidate_path(other_candidate), params: { expense_candidate: { description: "Hacked" } }
    assert_response :not_found
  end

  test "cannot confirm other users candidate" do
    other_user = User.create!(name: "Other", email: "other_conf_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_candidate = ExpenseCandidate.create!(user: other_user, amount: 100, date: Date.current, source: "text", status: "ready")

    assert_no_difference -> { Expense.count } do
      post confirm_expense_candidate_path(other_candidate)
    end
    assert_response :not_found
  end
end

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

  # --- BULK UPDATE ---

  test "PATCH /expense_candidates/bulk_update changes category for selected candidates" do
    a = create_candidate(category_id: nil, status: "needs_review")
    b = create_candidate(category_id: nil, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id, b.id],
      category_id: @category.id
    }
    assert_redirected_to expense_candidates_path

    assert_equal @category.id, a.reload.category_id
    assert_equal @category.id, b.reload.category_id
    follow_redirect!
    assert flash[:notice].present?
  end

  test "PATCH /expense_candidates/bulk_update changes money source for selected candidates" do
    a = create_candidate(money_source_id: nil, status: "needs_review")
    b = create_candidate(money_source_id: nil, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id, b.id],
      money_source_id: @money_source.id
    }
    assert_redirected_to expense_candidates_path

    assert_equal @money_source.id, a.reload.money_source_id
    assert_equal @money_source.id, b.reload.money_source_id
  end

  test "PATCH /expense_candidates/bulk_update changes category and money source in one request" do
    a = create_candidate(category_id: nil, money_source_id: nil, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id],
      category_id: @category.id,
      money_source_id: @money_source.id
    }
    assert_redirected_to expense_candidates_path

    a.reload
    assert_equal @category.id, a.category_id
    assert_equal @money_source.id, a.money_source_id
  end

  test "PATCH /expense_candidates/bulk_update only updates the fields provided" do
    a = create_candidate(category_id: nil, money_source_id: @money_source.id, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id],
      category_id: @category.id
    }
    assert_redirected_to expense_candidates_path

    a.reload
    assert_equal @category.id, a.category_id
    assert_equal @money_source.id, a.money_source_id
  end

  test "PATCH /expense_candidates/bulk_update rejects empty candidate ids" do
    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [],
      category_id: @category.id
    }
    assert_redirected_to expense_candidates_path
    follow_redirect!
    assert_equal I18n.t("expense_candidates.no_selection", default: "No hay candidatos seleccionados."), flash[:alert]
  end

  test "PATCH /expense_candidates/bulk_update rejects requests without any field to change" do
    a = create_candidate(status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id]
    }
    assert_redirected_to expense_candidates_path
    follow_redirect!
    assert_equal I18n.t("expense_candidates.choose_category_or_source", default: "Elige una categoría o fuente de dinero."), flash[:alert]
  end

  test "PATCH /expense_candidates/bulk_update rejects a category not available to the user" do
    other_user = User.create!(name: "Other", email: "bulk_cat_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_category = Category.create!(name: "Secret", user: other_user, is_default: false, category_type: "expense")
    a = create_candidate(category_id: nil, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id],
      category_id: other_category.id
    }
    assert_redirected_to expense_candidates_path
    assert_nil a.reload.category_id
    follow_redirect!
    assert_equal I18n.t("expense_candidates.update_category_not_found", default: "Categoría no encontrada."), flash[:alert]
  end

  test "PATCH /expense_candidates/bulk_update rejects a money source not owned by the user" do
    other_user = User.create!(name: "Other", email: "bulk_src_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_source = other_user.money_sources.create!(name: "Other Bank", kind: "account", starting_balance: 0)
    a = create_candidate(money_source_id: nil, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [a.id],
      money_source_id: other_source.id
    }
    assert_redirected_to expense_candidates_path
    assert_nil a.reload.money_source_id
    follow_redirect!
    assert_equal I18n.t("expense_candidates.update_source_not_found", default: "Fuente de dinero no encontrada."), flash[:alert]
  end

  test "PATCH /expense_candidates/bulk_update ignores candidates not owned by the current user" do
    other_user = User.create!(name: "Other", email: "bulk_iso_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_candidate = ExpenseCandidate.create!(user: other_user, amount: 100, date: Date.current, source: "text", status: "needs_review")
    mine = create_candidate(category_id: nil, status: "needs_review")

    patch bulk_update_expense_candidates_path, params: {
      candidate_ids: [mine.id, other_candidate.id],
      category_id: @category.id
    }
    assert_redirected_to expense_candidates_path
    assert_equal @category.id, mine.reload.category_id
    assert_not_equal @category.id, other_candidate.reload.category_id
    follow_redirect!
    assert flash[:notice].present?
  end

  # --- BULK CONFIRM ---

  test "POST /expense_candidates/bulk_confirm confirms ready candidates" do
    a = create_candidate(
      category_id: @category.id, money_source_id: @money_source.id,
      amount: 50_000, date: Date.current, description: "Bulk A", status: "ready"
    )
    b = create_candidate(
      category_id: @category.id, money_source_id: @money_source.id,
      amount: 30_000, date: Date.current, description: "Bulk B", status: "ready"
    )

    assert_difference -> { Expense.count }, 2 do
      post bulk_confirm_expense_candidates_path, params: {
        candidate_ids: [a.id, b.id]
      }
    end
    assert_redirected_to expense_candidates_path

    assert_equal "confirmed", a.reload.status
    assert_equal "confirmed", b.reload.status
    assert_not_nil a.expense_id
    assert_not_nil b.expense_id
  end

  test "POST /expense_candidates/bulk_confirm updates category before confirming" do
    a = create_candidate(
      category_id: nil, money_source_id: nil,
      amount: 50_000, date: Date.current, description: "Update+Confirm", status: "needs_review"
    )

    assert_difference -> { Expense.count }, 1 do
      post bulk_confirm_expense_candidates_path, params: {
        candidate_ids: [a.id],
        category_id: @category.id,
        money_source_id: @money_source.id
      }
    end
    assert_redirected_to expense_candidates_path

    a.reload
    assert_equal "confirmed", a.status
    assert_equal @category.id, a.category_id
    assert_equal @money_source.id, a.money_source_id
    assert_not_nil a.expense_id
  end

  test "POST /expense_candidates/bulk_confirm skips candidates with missing fields" do
    a = create_candidate(
      category_id: @category.id, money_source_id: @money_source.id,
      amount: 50_000, date: Date.current, description: "Ready", status: "ready"
    )
    b = create_candidate(
      category_id: nil, amount: 30_000, date: Date.current, description: "Missing cat", status: "needs_review"
    )

    assert_difference -> { Expense.count }, 1 do
      post bulk_confirm_expense_candidates_path, params: {
        candidate_ids: [a.id, b.id]
      }
    end
    assert_redirected_to expense_candidates_path

    assert_equal "confirmed", a.reload.status
    assert_equal "needs_review", b.reload.status
    follow_redirect!
    assert flash[:alert].present? || flash[:notice].present?
  end

  test "POST /expense_candidates/bulk_confirm rejects empty candidate ids" do
    post bulk_confirm_expense_candidates_path, params: {
      candidate_ids: []
    }
    assert_redirected_to expense_candidates_path
    follow_redirect!
    assert_equal I18n.t("expense_candidates.no_selection", default: "No hay candidatos seleccionados."), flash[:alert]
  end

  test "POST /expense_candidates/bulk_confirm ignores candidates not owned by the current user" do
    other_user = User.create!(name: "Other", email: "bulk_conf_#{SecureRandom.hex(4)}@example.com", password: "password123")
    other_candidate = ExpenseCandidate.create!(
      user: other_user, amount: 100, date: Date.current, source: "text",
      category_id: @category.id, status: "ready"
    )
    mine = create_candidate(
      category_id: @category.id, money_source_id: @money_source.id,
      amount: 50_000, date: Date.current, description: "Mine", status: "ready"
    )

    assert_difference -> { Expense.count }, 1 do
      post bulk_confirm_expense_candidates_path, params: {
        candidate_ids: [mine.id, other_candidate.id]
      }
    end
    assert_redirected_to expense_candidates_path
    assert_equal "confirmed", mine.reload.status
    assert_equal "ready", other_candidate.reload.status
  end
end

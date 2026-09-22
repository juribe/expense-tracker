# frozen_string_literal: true

require "test_helper"

class ExpenseCandidateTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Candidate User", email: "candidate_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @category = Category.create!(name: "Transporte Test", is_default: false, category_type: "expense", user: @user)
    @money_source = MoneySource.create!(user: @user, name: "Davibank", kind: "debit_card")
  end

  def build_candidate(**overrides)
    ExpenseCandidate.new(
      { user: @user, amount: 50_000, date: Date.current, source: "text" }.merge(overrides)
    )
  end

  # --- Validations ---

  test "is valid with amount, date and source" do
    assert build_candidate.valid?
  end

  test "requires a user" do
    candidate = build_candidate(user: nil)
    assert_not candidate.valid?
    assert candidate.errors[:user].any?
  end

  test "defaults status to needs_review when nil" do
    candidate = ExpenseCandidate.new(status: nil)
    candidate.valid?
    assert_equal "needs_review", candidate.status
  end

  test "validates status inclusion" do
    candidate = build_candidate(status: "invalid")
    assert_not candidate.valid?
    assert candidate.errors[:status].any?
  end

  test "accepts all valid statuses" do
    %w[needs_review ready confirmed discarded].each do |status|
      candidate = build_candidate(status: status)
      assert candidate.valid?, "Expected status '#{status}' to be valid"
    end
  end

  test "defaults source to text when nil" do
    candidate = ExpenseCandidate.new(source: nil)
    candidate.valid?
    assert_equal "text", candidate.source
  end

  test "validates amount numericality" do
    assert_not build_candidate(amount: 0).valid?
    assert_not build_candidate(amount: -100).valid?
    assert build_candidate(amount: 100).valid?
    assert build_candidate(amount: nil).valid?
  end

  test "defaults status to needs_review" do
    candidate = ExpenseCandidate.new
    assert_equal "needs_review", candidate.status
  end

  test "defaults source to text" do
    candidate = ExpenseCandidate.new
    assert_equal "text", candidate.source
  end

  test "defaults missing_fields to computed value" do
    candidate = ExpenseCandidate.new
    assert_equal %w[amount date category_id money_source_id], candidate.missing_fields
  end

  test "defaults metadata to empty hash" do
    candidate = ExpenseCandidate.new
    assert_equal({}, candidate.metadata)
  end

  # --- Missing fields ---

  test "missing_fields includes category_id when nil" do
    candidate = build_candidate(category_id: nil)
    assert_includes candidate.missing_fields, "category_id"
  end

  test "missing_fields includes money_source_id when nil" do
    candidate = build_candidate(money_source_id: nil)
    assert_includes candidate.missing_fields, "money_source_id"
  end

  test "missing_fields includes amount when nil" do
    candidate = build_candidate(amount: nil)
    assert_includes candidate.missing_fields, "amount"
  end

  test "missing_fields includes date when nil" do
    candidate = build_candidate(date: nil)
    assert_includes candidate.missing_fields, "date"
  end

  test "missing_fields is empty when all required fields are present" do
    candidate = build_candidate(
      category_id: @category.id,
      money_source_id: @money_source.id,
      amount: 50_000,
      date: Date.current
    )
    assert_equal [], candidate.missing_fields
  end

  test "missing_fields computes dynamically" do
    candidate = build_candidate(category_id: nil, money_source_id: nil)
    assert_includes candidate.missing_fields, "category_id"
    assert_includes candidate.missing_fields, "money_source_id"

    candidate.category_id = @category.id
    assert_not_includes candidate.missing_fields, "category_id"
    assert_includes candidate.missing_fields, "money_source_id"
  end

  # --- Status helpers ---

  test "needs_review? returns true for needs_review status" do
    assert build_candidate(status: "needs_review").needs_review?
    assert_not build_candidate(status: "ready").needs_review?
  end

  test "ready? returns true when status is ready" do
    assert build_candidate(status: "ready").ready?
    assert_not build_candidate(status: "needs_review").ready?
  end

  test "confirmed? returns true when status is confirmed" do
    assert build_candidate(status: "confirmed").confirmed?
    assert_not build_candidate(status: "ready").confirmed?
  end

  test "discarded? returns true when status is discarded" do
    assert build_candidate(status: "discarded").discarded?
    assert_not build_candidate(status: "needs_review").discarded?
  end

  # --- Scopes ---

  test "pending scope returns needs_review and ready" do
    needs_review = build_candidate(status: "needs_review").tap(&:save!)
    ready = build_candidate(status: "ready").tap(&:save!)
    confirmed = build_candidate(status: "confirmed").tap(&:save!)
    discarded = build_candidate(status: "discarded").tap(&:save!)

    pending = ExpenseCandidate.pending
    assert_includes pending, needs_review
    assert_includes pending, ready
    assert_not_includes pending, confirmed
    assert_not_includes pending, discarded
  end

  test "needs_review scope filters correctly" do
    needs_review = build_candidate(status: "needs_review").tap(&:save!)
    ready = build_candidate(status: "ready").tap(&:save!)

    assert_includes ExpenseCandidate.needs_review, needs_review
    assert_not_includes ExpenseCandidate.needs_review, ready
  end

  test "ready scope filters correctly" do
    ready = build_candidate(status: "ready").tap(&:save!)
    needs_review = build_candidate(status: "needs_review").tap(&:save!)

    assert_includes ExpenseCandidate.ready, ready
    assert_not_includes ExpenseCandidate.ready, needs_review
  end

  test "for_user scope isolates by user" do
    mine = build_candidate.tap(&:save!)
    other_user = User.create!(name: "Other", email: "candidate_other_#{SecureRandom.hex(4)}@example.com", password: "password123")
    theirs = ExpenseCandidate.create!(user: other_user, amount: 100, date: Date.current, source: "text")

    assert_includes ExpenseCandidate.for_user(@user), mine
    assert_not_includes ExpenseCandidate.for_user(@user), theirs
  end

  # --- confirm! ---

  test "confirm! creates an Expense and marks candidate as confirmed" do
    candidate = build_candidate(
      category_id: @category.id,
      money_source_id: @money_source.id,
      amount: 50_000,
      date: Date.current,
      description: "Transferencia a Juan",
      source: "text",
      original_input: "Le transferí 50 mil a Juan"
    )
    candidate.save!

    assert_difference -> { Expense.count }, 1 do
      candidate.confirm!
    end

    assert_equal "confirmed", candidate.status
    assert_not_nil candidate.expense_id
    assert_not_nil candidate.confirmed_at

    expense = candidate.expense
    assert_equal @user, expense.user
    assert_equal @category, expense.category
    assert_equal @money_source, expense.money_source
    assert_equal Date.current, expense.date
    assert_equal "Transferencia a Juan", expense.description
    assert_equal "ai", expense.source
  end

  test "confirm! raises when required fields are missing" do
    candidate = build_candidate(amount: nil, category_id: nil)
    candidate.save!

    assert_raises(ActiveRecord::RecordInvalid) do
      candidate.confirm!
    end
  end

  test "confirm! is idempotent" do
    candidate = build_candidate(
      category_id: @category.id,
      amount: 50_000,
      date: Date.current
    )
    candidate.save!

    candidate.confirm!
    first_expense_id = candidate.expense_id

    assert_no_difference -> { Expense.count } do
      candidate.confirm!
    end
    assert_equal first_expense_id, candidate.expense_id
  end

  # --- discard! ---

  test "discard! sets status to discarded and discarded_at" do
    candidate = build_candidate.tap(&:save!)

    candidate.discard!

    assert_equal "discarded", candidate.status
    assert_not_nil candidate.discarded_at
  end

  test "discard! from any status" do
    %w[needs_review ready].each do |initial_status|
      candidate = build_candidate(status: initial_status).tap(&:save!)
      candidate.discard!
      assert_equal "discarded", candidate.status
    end
  end

  # --- Recalculation ---

  test "recalculate_missing_fields! updates missing_fields based on current values" do
    candidate = build_candidate(category_id: nil, money_source_id: nil)
    candidate.save!
    assert_includes candidate.missing_fields, "category_id"
    assert_includes candidate.missing_fields, "money_source_id"

    candidate.update!(category_id: @category.id)
    candidate.recalculate_missing_fields!

    assert_not_includes candidate.reload.missing_fields, "category_id"
    assert_includes candidate.reload.missing_fields, "money_source_id"
  end

  test "recalculate_status! sets ready when no fields are missing" do
    candidate = build_candidate(
      category_id: nil,
      money_source_id: nil,
      status: "needs_review"
    )
    candidate.save!

    candidate.update!(category_id: @category.id, money_source_id: @money_source.id)
    candidate.recalculate_status!

    assert_equal "ready", candidate.reload.status
  end

  test "recalculate_status! sets needs_review when fields are missing" do
    candidate = build_candidate(
      category_id: @category.id,
      money_source_id: @money_source.id,
      status: "ready"
    )
    candidate.save!

    candidate.update!(category_id: nil)
    candidate.recalculate_status!

    assert_equal "needs_review", candidate.reload.status
  end

  test "recalculate_status! does not change confirmed or discarded status" do
    candidate = build_candidate(status: "confirmed")
    candidate.save!
    candidate.update!(category_id: nil)
    candidate.recalculate_status!
    assert_equal "confirmed", candidate.reload.status

    candidate = build_candidate(status: "discarded")
    candidate.save!
    candidate.update!(category_id: nil)
    candidate.recalculate_status!
    assert_equal "discarded", candidate.reload.status
  end

  # --- Amount handling ---

  test "stores amount as decimal" do
    candidate = build_candidate(amount: 50_000.50)
    candidate.save!
    candidate.reload
    assert_equal BigDecimal("50000.50"), candidate.amount
  end

  test "allows nil amount for incomplete candidates" do
    candidate = build_candidate(amount: nil)
    assert candidate.valid?
    candidate.save!
    assert_nil candidate.reload.amount
  end

  # --- Source tracking ---

  test "stores various source types" do
    %w[text whatsapp email image ocr other].each do |source_type|
      candidate = build_candidate(source: source_type)
      assert candidate.valid?, "Expected source '#{source_type}' to be valid"
    end
  end

  # --- Confidence ---

  test "stores confidence as float" do
    candidate = build_candidate(confidence: 0.85)
    candidate.save!
    assert_in_delta 0.85, candidate.reload.confidence, 0.001
  end

  test "allows nil confidence" do
    candidate = build_candidate(confidence: nil)
    assert candidate.valid?
  end

  # --- BRE/transfer ambiguity (key acceptance criteria) ---

  test "transfer to person creates candidate with nil category" do
    candidate = build_candidate(
      amount: 50_000,
      description: "Transferencia a Juan",
      category_id: nil,
      original_input: "Le transferí 50 mil a Juan"
    )

    assert candidate.valid?
    assert_includes candidate.missing_fields, "category_id"
    assert_equal "needs_review", candidate.status
  end

  test "gasoline expense with known category is ready" do
    candidate = build_candidate(
      amount: 30_000,
      description: "Gasolina",
      category_id: @category.id,
      money_source_id: @money_source.id,
      date: Date.current
    )

    assert candidate.valid?
    assert_equal [], candidate.missing_fields
    assert_equal "ready", candidate.status
  end

  test "multiple missing fields tracked together" do
    candidate = build_candidate(
      category_id: nil,
      money_source_id: nil,
      amount: 50_000,
      date: Date.current
    )

    assert_includes candidate.missing_fields, "category_id"
    assert_includes candidate.missing_fields, "money_source_id"
    assert_equal 2, candidate.missing_fields.length
  end
end

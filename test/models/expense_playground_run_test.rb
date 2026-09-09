# frozen_string_literal: true

require "test_helper"

class ExpensePlaygroundRunTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Run User", email: "run@example.com", password: "password123")
    @result = ExpensePlayground::ProcessingService::Result.new(
      candidate: ExpenseCandidate.new(amount: 50_000, category_name: "Food", date: Date.current,
        source: "playground", confidence: 0.9),
      steps: { input: { type: "text", text: "50 mil" }, ocr: { applicable: false } },
      errors: [],
      warnings: [],
      duration_ms: 12,
      engine: "heuristic"
    )
  end

  test "records a successful run without image payloads" do
    run = ExpensePlaygroundRun.record!(user: @user, input_type: "text", input_label: "50 mil", result: @result)

    assert run.ok?
    assert_equal "text", run.input_type
    assert_equal "heuristic", run.engine
    assert_equal 12, run.duration_ms
    assert_equal BigDecimal(50_000.to_s), BigDecimal(run.candidate["amount"].to_s)
    assert_nil run.expense_id
  end

  test "records a failed run" do
    failed = ExpensePlayground::ProcessingService::Result.new(
      candidate: nil, steps: { input: { type: "text" } }, errors: [ "boom" ],
      warnings: [], duration_ms: 3, engine: "heuristic"
    )

    run = ExpensePlaygroundRun.record!(user: @user, input_type: "text", result: failed)

    assert_equal "failed", run.status
    assert_not run.ok?
    assert_equal [ "boom" ], run.error_messages
  end

  test "truncates long labels and requires a user" do
    run = ExpensePlaygroundRun.record!(
      user: @user, input_type: "text", input_label: "x" * 500, result: @result
    )
    assert_equal 200, run.input_label.length

    assert_raises(ActiveRecord::RecordInvalid) do
      ExpensePlaygroundRun.record!(user: nil, input_type: "text", result: @result)
    end
  end

  test "history entry exposes the UI projection" do
    run = ExpensePlaygroundRun.record!(user: @user, input_type: "text", input_label: "50 mil", result: @result)
    entry = run.to_history_entry

    assert_equal run.id, entry[:id]
    assert_equal "text", entry[:type]
    assert entry[:ok]
    assert_equal 0.9, entry[:confidence]
    assert entry[:candidate].present?
  end

  test "scoped to the owning user via recent_first" do
    ExpensePlaygroundRun.record!(user: @user, input_type: "text", result: @result)

    other = User.create!(name: "Other", email: "other-run@example.com", password: "password123")
    ExpensePlaygroundRun.record!(user: other, input_type: "text", result: @result)

    assert_equal 1, @user.expense_playground_runs.count
  end
end

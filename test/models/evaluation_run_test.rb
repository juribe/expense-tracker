# frozen_string_literal: true

require "test_helper"

class EvaluationRunTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "run-model-eval@example.com", password: "password123")
    @run = EvaluationRun.create!(
      user: @user, dataset_name: "gastos.csv", dataset_version: "abc123",
      provider: "openrouter", model: "upstage/solar-pro4", prompt_version: "expense-extraction-v1",
      status: "running", total_cases: 2
    )
  end

  def case_row(row_number:, status:)
    EvaluationCase.create!(
      evaluation_run: @run, row_number: row_number, message: "mensaje #{row_number}",
      expected_json: { "amount" => 1 }, status: status
    )
  end

  test "progress tracks finished cases against total" do
    assert_equal 0.0, @run.progress

    case_row(row_number: 2, status: "passed")
    assert_equal 0.5, @run.progress
  end

  test "update_progress! completes the run once every case is terminal and freezes metrics" do
    case_row(row_number: 2, status: "passed")
    case_row(row_number: 3, status: "failed")

    @run.update_progress!

    assert @run.completed?
    assert_not_nil @run.completed_at
    assert_equal 0.5, @run.metric("overall_accuracy")
    assert_equal 2, @run.metric("total_cases")
  end

  test "update_progress! moves a pending run to running while cases remain" do
    pending_run = EvaluationRun.create!(
      user: @user, dataset_name: "gastos.csv", provider: "openrouter", model: "m",
      status: "pending", total_cases: 2
    )

    pending_run.update_progress!

    assert pending_run.running?
    assert_not_nil pending_run.started_at
  end

  test "fail! records the failure reason in metrics" do
    case_row(row_number: 2, status: "pending")

    @run.fail!(reason: "headers missing")

    assert @run.failed?
    assert_equal "headers missing", @run.metric("error")
  end

  test "to_evaluation_entry is JSON-safe and includes reproducibility fields" do
    entry = @run.to_evaluation_entry

    assert_equal @run.id, entry[:id]
    assert_equal "gastos.csv", entry[:dataset_name]
    assert_equal "abc123", entry[:dataset_version]
    assert_equal "openrouter", entry[:provider]
    assert_equal "expense-extraction-v1", entry[:prompt_version]
    assert_equal 0.0, entry[:progress]
    assert entry[:created_at].is_a?(String)
  end
end

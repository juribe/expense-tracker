# frozen_string_literal: true

require "test_helper"

class ExpensePlaygroundEvaluationsMetricsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "metrics-eval@example.com", password: "password123")
    @run = EvaluationRun.create!(user: @user, dataset_name: "gastos.csv",
                                 dataset_version: "abc123", provider: "openrouter",
                                 model: "m", total_cases: 3, status: "running")
  end

  def case_row(row_number:, status:, field_results: [], json_valid: false, cost: 0, error: nil)
    EvaluationCase.create!(
      evaluation_run: @run, row_number: row_number, message: "m#{row_number}",
      expected_json: { "amount" => 1 }, status: status, json_valid: json_valid,
      field_results: field_results, cost: cost, error: error
    )
  end

  def field(field, matched:)
    { "field" => field, "compared" => true, "matched" => matched }
  end

  test "aggregates passed/failed/errored counts and accuracy" do
    case_row(row_number: 1, status: "passed", field_results: [ field("amount", matched: true) ], cost: 0.5)
    case_row(row_number: 2, status: "failed", field_results: [ field("amount", matched: false) ])
    case_row(row_number: 3, status: "error", error: "AI not configured")

    metrics = ExpensePlayground::Evaluations::Metrics.for(@run)

    assert_equal 3, metrics["total_cases"]
    assert_equal 1, metrics["passed"]
    assert_equal 1, metrics["failed"]
    assert_equal 1, metrics["errored"]
    assert_equal 0, metrics["pending"]
    assert_equal 0.3333, metrics["accuracy"]
    assert_equal 0.5, metrics["cost"]
    assert_equal 2, metrics.dig("fields", "amount", "compared")
    assert_equal 1, metrics.dig("fields", "amount", "passed")
  end

  test "field totals only count compared fields across terminal rows" do
    case_row(row_number: 1, status: "passed",
             field_results: [ field("amount", matched: true), field("category", matched: true) ])
    case_row(row_number: 2, status: "failed",
             field_results: [ field("amount", matched: false), field("category", matched: true) ])
    case_row(row_number: 3, status: "pending")

    metrics = ExpensePlayground::Evaluations::Metrics.for(@run)

    assert_equal 2, metrics.dig("fields", "amount", "compared")
    assert_equal 1, metrics.dig("fields", "amount", "passed")
    assert_equal 2, metrics.dig("fields", "category", "compared")
    assert_equal 2, metrics.dig("fields", "category", "passed")
  end

  test "takes pending cases into account before completion" do
    case_row(row_number: 1, status: "passed", field_results: [ field("amount", matched: true) ])

    metrics = ExpensePlayground::Evaluations::Metrics.for(@run)
    assert_equal 2, metrics["pending"]
    assert_equal 0.3333, metrics["accuracy"]
  end

  test "dotted key reads work on persisted metrics" do
    metrics = {
      "total_cases" => 5,
      "fields" => { "amount" => { "compared" => 5, "passed" => 4 } }
    }

    assert_equal 5, ExpensePlayground::Evaluations::Metrics.metric(metrics, "total_cases")
    assert_equal 4, ExpensePlayground::Evaluations::Metrics.metric(metrics, "fields.amount.passed")
    assert_nil ExpensePlayground::Evaluations::Metrics.metric(metrics, "fields.date.passed")
  end
end
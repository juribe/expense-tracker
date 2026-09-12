# frozen_string_literal: true

require "test_helper"

class ExpensePlaygroundEvaluationsMetricsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "metrics-eval@example.com", password: "password123")
    @run = EvaluationRun.create!(user: @user, dataset_name: "gastos.csv",
                                 dataset_version: "abc123", provider: "openrouter",
                                 model: "m", total_cases: 3, status: "running")
  end

  def case_row(row_number:, status:, field_results: [], json_valid: false,
               cost: 0, input_cost: 0, output_cost: 0, latency_ms: 0,
               input_tokens: 0, output_tokens: 0, error: nil)
    EvaluationCase.create!(
      evaluation_run: @run, row_number: row_number, message: "m#{row_number}",
      expected_json: { "amount" => 1 }, status: status, json_valid: json_valid,
      field_results: field_results, cost: cost, input_cost: input_cost,
      output_cost: output_cost, latency_ms: latency_ms,
      input_tokens: input_tokens, output_tokens: output_tokens, error: error
    )
  end

  def field(field, matched:)
    { "field" => field, "compared" => true, "matched" => matched }
  end

  test "aggregates passed/failed/errored counts and accuracy" do
    case_row(row_number: 1, status: "passed", json_valid: true,
             field_results: [ field("amount", matched: true) ],
             input_cost: 0.2, output_cost: 0.3, latency_ms: 100, input_tokens: 100, output_tokens: 20)
    case_row(row_number: 2, status: "failed", field_results: [ field("amount", matched: false) ],
             latency_ms: 200, input_tokens: 90, output_tokens: 15)
    case_row(row_number: 3, status: "error", error: "AI not configured")

    metrics = ExpensePlayground::Evaluations::Metrics.for(@run)

    assert_equal 3, metrics["total_cases"]
    assert_equal 1, metrics["passed_cases"]
    assert_equal 1, metrics["failed_cases"]
    assert_equal 1, metrics["errored"]
    assert_equal 0, metrics["pending"]
    assert_equal 0.3333, metrics["accuracy"]
    assert_equal 0.3333, metrics["overall_accuracy"]
    assert_equal 0.3333, metrics["full_record_accuracy"]
    assert_equal 0.2, metrics["input_cost"]
    assert_equal 0.3, metrics["output_cost"]
    assert_equal 0.5, metrics["cost"]
    assert_equal 0.5, metrics["total_cost"]
    assert_equal 150.0, metrics["average_latency"]
    assert_equal 190, metrics["total_input_tokens"]
    assert_equal 35, metrics["total_output_tokens"]
    assert_equal 0.3333, metrics["json_validity"]
    assert_equal 2, metrics.dig("fields", "amount", "compared")
    assert_equal 1, metrics.dig("fields", "amount", "passed")
    assert_equal 0.5, metrics["amount_accuracy"]
    assert metrics.key?("date_accuracy")
    assert_nil metrics["date_accuracy"]
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

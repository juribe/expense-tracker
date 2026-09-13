# frozen_string_literal: true

require "test_helper"

# Runs one evaluation case through the REAL existing Expense Playground
# pipeline (ExpenseParser → Ai::Router override → normalization → validation →
# ResultBuilder → Comparator) exactly as the background job does, with the AI
# response stubbed. This is the core "the evaluation reuses the same pipeline"
# guarantee: the only injected piece is the provider/model under test.
class ExpensePlaygroundEvaluationCaseJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(email: "case-eval@example.com", password: "password123")
    @run = EvaluationRun.create!(
      user: @user, dataset_name: "gastos.csv", dataset_version: "abc123",
      provider: "openrouter", model: "upstage/solar-pro4",
      prompt_version: "expense-extraction-v1",
      status: "running", total_cases: 1
    )
  end

  def case_row(expected_json: { "amount" => 20_000 })
    EvaluationCase.create!(
      evaluation_run: @run, row_number: 2, message: "me gasté 20mil hoy en almuerzo",
      expected_json: expected_json, status: "pending"
    )
  end

  def stub_provider(fake, &block)
    stub_method(Ai::Providers, :build, ->(provider:, model:, **_opts) { fake }, &block)
  end

  def ok_response(amount: 20_000, description: "almuerzo", category: "Restaurants", tokens: {})
    {
      content: {
        "expenses" => [
          {
            "amount" => amount,
            "category" => category,
            "description" => description,
            "transaction_date" => Date.current.iso8601,
            "confidence" => 0.99,
            "create_category" => false
          }
        ]
      }.to_json,
      input_tokens: 120,
      output_tokens: 40
    }.merge(tokens)
  end

  test "passes a case through the real pipeline and stores result + usage" do
    case_record = case_row(expected_json: { "amount" => 20_000, "activity" => "almuerzo" })
    stub_provider(FakeAiProvider.new(responses: [ ok_response ])) do
      ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
    end

    case_record.reload
    assert_equal "passed", case_record.status
    assert_predicate case_record, :json_valid?
    assert_equal "almuerzo", case_record.actual_json["activity"]
    assert_equal 120, case_record.input_tokens
    assert_equal 40, case_record.output_tokens
    assert_equal 0.0, case_record.cost.to_f
    assert case_record.field_results.any? { |r| r["field"] == "amount" && r["matched"] }
    assert_equal "completed", @run.reload.status
  end

  test "marks the case failed when the final result differs from expected" do
    case_record = case_row(expected_json: { "amount" => 20_000, "activity" => "uber" })
    stub_provider(FakeAiProvider.new(responses: [ ok_response ])) do
      ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
    end

    case_record.reload
    assert_equal "failed", case_record.status
    activity_result = case_record.field_results.find { |r| r["field"] == "activity" }
    assert_equal false, activity_result["matched"]
    assert_equal "almuerzo", case_record.actual_json["activity"]
  end

  test "marks the case error when the final result is invalid JSON and never crashes the run" do
    case_record = case_row
    stub_provider(FakeAiProvider.new(responses: [ "this is not json", "this is not json", "this is not json" ])) do
      with_active_job_adapter(:test) do
        3.times do
          ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
          enqueued_jobs.clear
        end
      end
    end

    case_record.reload
    assert_equal "error", case_record.status
    assert case_record.error.present?
    assert_equal "completed", @run.reload.status
  end

  test "marks error and re-enqueues on provider failure; recovers on the next attempt" do
    case_record = case_row
    stub_provider(FakeAiProvider.new(responses: [ Ai::Provider::Error.new("timeout"), ok_response ])) do
      with_active_job_adapter(:test) do
        ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)

        case_record.reload
        assert_equal "pending", case_record.status
        assert_equal 1, case_record.attempts
        assert_equal 1, enqueued_jobs.count { |j| j[:job] == ExpensePlaygroundEvaluationCaseJob }

        enqueued_jobs.clear
        ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)

        case_record.reload
        assert_equal "passed", case_record.status
        assert_equal 1, case_record.attempts
        assert_equal 0, enqueued_jobs.count
      end
    end
  end

  test "a provider failure escalates to error status after MAX_ATTEMPTS" do
    case_record = case_row
    stub_provider(FakeAiProvider.new(responses: [
      Ai::Provider::Error.new("timeout"), Ai::Provider::Error.new("timeout"),
      Ai::Provider::Error.new("timeout")
    ])) do
      with_active_job_adapter(:test) do
        3.times do
          ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
          enqueued_jobs.clear
        end

        assert_equal "error", case_record.reload.status
        assert_equal 2, case_record.reload.attempts
      end
    end
  end

  test "an unknown or unconfigured provider fails the case without calling any AI" do
    case_record = case_row
    stub_method(Ai::Providers, :build, ->(*) { raise ArgumentError, "no client" }) do
      with_active_job_adapter(:test) do
        3.times do
          ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
          enqueued_jobs.clear
        end
      end
    end

    case_record.reload
    assert_equal "error", case_record.status
    assert_equal 2, case_record.attempts
    assert_includes case_record.error, "not configured"
    assert case_record.actual_json.nil?
    assert_equal "completed", @run.reload.status
  end

  test "is idempotent: re-running a passed case never overwrites it" do
    case_record = case_row(expected_json: { "amount" => 20_000, "activity" => "almuerzo" })
    stub_provider(FakeAiProvider.new(responses: [ ok_response, ok_response(description: "cafe") ])) do
      ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
      ExpensePlaygroundEvaluationCaseJob.perform_now(case_record.id)
    end

    case_record.reload
    assert_equal "passed", case_record.status
    assert_equal "almuerzo", case_record.actual_json["activity"]
    assert_equal 1, @run.reload.evaluation_cases.where(status: "passed").count
  end
end

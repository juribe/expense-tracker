# frozen_string_literal: true

require "test_helper"
require "csv"

class ExpensePlaygroundEvaluationsRunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @user = User.create!(email: "runner-eval@example.com", password: "password123")
  end

  def csv_for(rows)
    CSV.generate { |csv| rows.each { |row| csv << row } }
  end

  def dataset
    csv_for([
      %w[message expected_json],
      [ "me gasté 20mil hoy en almuerzo", { "intent" => "expense", "amount" => 20_000 }.to_json ],
      [ "pagué 10 lucas en café", { "intent" => "expense", "amount" => 10_000 }.to_json ]
    ])
  end

  def start
    with_active_job_adapter(:test) do
      ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: dataset, filename: "gastos.csv",
        provider: "openrouter", model: "upstage/solar-pro4"
      )
    end
  end

  test "creates the run and one case per dataset row" do
    result = start

    assert result.invalid == false
    run = result.run
    assert_equal "gastos.csv", run.dataset_name
    assert_equal 2, run.total_cases
    assert_equal "running", run.status
    assert_equal "openrouter", run.provider
    assert_equal "upstage/solar-pro4", run.model
    assert_equal 1, run.evaluation_cases.recent_first.count
    assert_equal [ 2, 3 ], run.evaluation_cases.recent_first.pluck(:row_number)
  end

  test "is idempotent: re-submitting the same dataset+params replays the run" do
    first = start
    second = start

    assert_equal false, second.invalid
    assert_equal true, second.replayed
    assert_equal first.run.id, second.run.id
    assert_equal 1, EvaluationRun.where(user: @user).count
  end

  test "different provider or model creates a new run" do
    first = start
    second = start.then do
      with_active_job_adapter(:test) do
        ExpensePlayground::Evaluations::Runner.start(
          user: @user, content: dataset, filename: "gastos.csv",
          provider: "mistral", model: "mistral-small-latest"
        )
      end
    end

    assert_equal false, second.replayed
    assert_not_equal first.run.id, second.run.id
  end

  test "invalid datasets fail before any run or case is created" do
    result = with_active_job_adapter(:test) do
      ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: "message,expected_json\n,{}", filename: "gastos.csv",
        provider: "openrouter", model: "m"
      )
    end

    assert result.invalid
    assert_nil result.run_id
    assert result.errors.any? { |error| error.include?("Row 2") }
    assert_equal 0, EvaluationRun.where(user: @user).count
    assert_equal 0, EvaluationCase.count
  end

  test "missing provider or model is rejected" do
    result = with_active_job_adapter(:test) do
      ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: dataset, filename: "gastos.csv", provider: "", model: "m"
      )
    end

    assert result.invalid
    assert_match(/provider and model/, result.errors.join(" "))
  end

  test "enqueues one background job per case" do
    with_active_job_adapter(:test) do
      assert_enqueued_with(job: ExpensePlaygroundEvaluationCaseJob) do
        start
      end
      assert_equal 2, enqueued_jobs.size
    end
  end
end
# frozen_string_literal: true

require "test_helper"
require "csv"

class ExpensePlaygroundEvaluationControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "PG Evaluation User",
                         email: "pg-eval-controller-#{SecureRandom.hex(6)}@example.com",
                         password: "password123")
    sign_in @user
  end

  def dataset_csv
    CSV.generate do |csv|
      csv << [ "message", "expected_json" ]
      csv << [ "me gasté 20mil hoy en almuerzo", { "intent" => "expense", "amount" => 20_000 }.to_json ]
      csv << [ "pagué 10 lucas en café", { "intent" => "expense", "amount" => 10_000 }.to_json ]
    end
  end

  def start_params
    { filename: "gastos.csv", dataset: dataset_csv, provider: "openrouter", model: "upstage/solar-pro4" }
  end

  test "GET /expense-playground/evaluations lists runs recent first" do
    EvaluationRun.create!(user: @user, dataset_name: "a.csv", dataset_version: "v1",
                          provider: "openrouter", model: "m", status: "completed", total_cases: 1)

    get expense_playground_evaluations_path(format: :json)

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["runs"].length
    assert_equal "a.csv", data["runs"].first["dataset_name"]
  end

  test "POST start_evaluation creates the run, the cases and queues one job per case" do
    with_active_job_adapter(:test) do
      assert_difference -> { EvaluationRun.count } => 1, -> { EvaluationCase.count } => 2 do
        post expense_playground_start_evaluation_path(format: :json), params: start_params
      end
    end

    assert_response :created
    data = JSON.parse(response.body)
    assert_equal true, data["ok"]
    run = EvaluationRun.find(data["run"]["id"])
    assert_equal "running", run.status
    assert_equal 2, run.total_cases
    assert_equal "openrouter", run.provider
  end

  test "POST start_evaluation is idempotent for the same dataset+model" do
    first = nil
    second = nil
    with_active_job_adapter(:test) do
      post expense_playground_start_evaluation_path(format: :json), params: start_params
      first = JSON.parse(response.body)["run"]["id"]

      post expense_playground_start_evaluation_path(format: :json), params: start_params
      second = JSON.parse(response.body)
    end

    assert_equal 1, EvaluationRun.count
    assert_equal first, second["run"]["id"]
    assert_equal true, second["replayed"]
  end

  test "POST start_evaluation rejects a dataset with invalid rows" do
    post expense_playground_start_evaluation_path(format: :json),
         params: start_params.merge(dataset: "message,expected_json\n,{}")

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal false, data["ok"]
    assert data["errors"].any? { |error| error.include?("Row 2") }
    assert_equal 0, EvaluationRun.count
  end

  test "GET evaluation returns the run plus its cases" do
    run = ExpensePlayground::Evaluations::Runner.start(
      user: @user, content: dataset_csv, filename: "gastos.csv",
      provider: "openrouter", model: "upstage/solar-pro4"
    ).run

    get expense_playground_evaluation_path(run, format: :json)

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "gastos.csv", data["run"]["dataset_name"]
    assert_equal 2, data["cases"].length
  end

  $hangwd_occurrences = 0
  tp = TracePoint.new(:call) do |t|
    next unless t.defined_class == ExpensePlaygroundEvaluationControllerTest
    next unless t.method_id.to_s.start_with?("test_GET_evaluation_cases")
    $hangwd_occurrences += 1
    if $hangwd_occurrences <= 3
      puts "> HANGWD RECURSION ENTRY ##{$hangwd_occurrences}"
      puts Thread.current.backtrace.first(30).map { |f| "    #{f}" }.join("\n")
    end
  end
  tp.enable
  test "GET evaluation_cases supports status and message filters" do
    $hangwd_occurrences += 1
    puts "> HANGWD START ##{$hangwd_occurrences}"
    if $hangwd_occurrences <= 3
      puts "> HANGWD BT\n" + caller.map { |f| "    #{f}" }.join("\n")
    end
    with_active_job_adapter(:test) do
      run = ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: dataset_csv, filename: "gastos.csv",
        provider: "openrouter", model: "upstage/solar-pro4"
      ).run
      puts "> HANGWD after start, run=#{run&.id}"
      run.evaluation_cases.first.update!(status: "failed")
      #puts "> HANGWD after update"
    end
    puts "> HANGWD block done, run id=#{run&.id}"

    get expense_playground_evaluation_cases_path(run, format: :json, status: "failed")
    puts "> HANGWD after GET status-filtered"
    failed = JSON.parse(response.body)
    assert_equal 1, failed["total"]
    assert_equal 1, failed["cases"].length
    assert_equal "failed", failed["cases"].first["status"]

    get expense_playground_evaluation_cases_path(run, format: :json, q: "café")
    filtered = JSON.parse(response.body)
    assert_equal 1, filtered["total"]
    assert_includes filtered["cases"].first["message"], "café"
  end

  test "POST retry_evaluation resets failed cases to pending and re-enqueues them" do
    with_active_job_adapter(:test) do
run = ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: dataset_csv, filename: "gastos.csv",
        provider: "openrouter", model: "upstage/solar-pro4"
      ).run
      enqueued_jobs.clear
      failed_case = run.evaluation_cases.first
      failed_case.update!(status: "failed", error: "mismatch")

      post expense_playground_retry_evaluation_path(run, format: :json)

      assert_response :success
      data = JSON.parse(response.body)
      assert_equal 1, data["rerun_count"]
      assert_equal "pending", failed_case.reload.status
      assert_equal "running", run.reload.status
      assert_equal 1, enqueued_jobs.count { |j| j[:job] == ExpensePlaygroundEvaluationCaseJob }
    end
  end
end
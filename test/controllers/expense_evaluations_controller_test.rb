# frozen_string_literal: true

require "test_helper"
require "csv"

class ExpenseEvaluationsControllerTest < ActionDispatch::IntegrationTest
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
    { filename: "gastos.csv", dataset: dataset_csv, provider: "openrouter", model: "mistral/mistral-small-latest" }
  end

  test "GET /expense-evaluations lists runs recent first" do
    EvaluationRun.create!(user: @user, dataset_name: "a.csv", dataset_version: "v1",
                          provider: "openrouter", model: "m", status: "completed", total_cases: 1)

    get expense_evaluations_path(format: :json)

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["runs"].length
    assert_equal "a.csv", data["runs"].first["dataset_name"]
  end

  test "POST start_evaluation creates the run, the cases and queues one job per case" do
    with_active_job_adapter(:test) do
      assert_difference -> { EvaluationRun.count } => 1, -> { EvaluationCase.count } => 2 do
        post expense_evaluations_start_path(format: :json), params: start_params
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
      post expense_evaluations_start_path(format: :json), params: start_params
      first = JSON.parse(response.body)["run"]["id"]

      post expense_evaluations_start_path(format: :json), params: start_params
      second = JSON.parse(response.body)
    end

    assert_equal 1, EvaluationRun.count
    assert_equal first, second["run"]["id"]
    assert_equal true, second["replayed"]
  end

  test "POST start_evaluation with force_new starts a fresh run for the same dataset" do
    first = nil
    second = nil
    with_active_job_adapter(:test) do
      post expense_evaluations_start_path(format: :json), params: start_params
      first = JSON.parse(response.body)["run"]["id"]

      post expense_evaluations_start_path(format: :json),
           params: start_params.merge(force_new: true, filename: "gastos_v2.csv")
      second = JSON.parse(response.body)
    end

    assert_equal 2, EvaluationRun.count
    assert_not_equal first, second["run"]["id"]
    assert_equal false, second["replayed"]
    assert_equal "gastos_v2.csv", second["run"]["dataset_name"]
  end

  test "POST start_evaluation rejects a dataset with invalid rows" do
    post expense_evaluations_start_path(format: :json),
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
      provider: "openrouter", model: "mistral/mistral-small-latest"
    ).run

    get expense_evaluation_path(run, format: :json)

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "gastos.csv", data["run"]["dataset_name"]
    assert_equal 2, data["cases"].length
  end

  test "GET evaluation_cases supports status and message filters" do
    run = nil
    with_active_job_adapter(:test) do
      run = ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: dataset_csv, filename: "gastos.csv",
        provider: "openrouter", model: "mistral/mistral-small-latest"
      ).run
      run.evaluation_cases.first.update!(status: "failed")
    end

    get expense_evaluation_cases_path(run, format: :json, status: "failed")
    failed = JSON.parse(response.body)
    assert_equal 2, failed["total"]
    assert_equal 1, failed["cases"].length
    assert_equal "failed", failed["cases"].first["status"]

    get expense_evaluation_cases_path(run, format: :json, q: "café")
    filtered = JSON.parse(response.body)
    assert_equal 2, filtered["total"]
    assert_equal 1, filtered["cases"].length
    assert_includes filtered["cases"].first["message"], "café"
  end

  test "POST retry_evaluation resets failed cases to pending and re-enqueues them" do
    with_active_job_adapter(:test) do
run = ExpensePlayground::Evaluations::Runner.start(
        user: @user, content: dataset_csv, filename: "gastos.csv",
        provider: "openrouter", model: "mistral/mistral-small-latest"
      ).run
      enqueued_jobs.clear
      failed_case = run.evaluation_cases.first
      failed_case.update!(status: "failed", error: "mismatch")

      post expense_evaluation_retry_path(run, format: :json)

      assert_response :success
      data = JSON.parse(response.body)
      assert_equal 1, data["rerun_count"]
      assert_equal "pending", failed_case.reload.status
      assert_equal "running", run.reload.status
      assert_equal 1, enqueued_jobs.count { |j| j[:job] == ExpensePlaygroundEvaluationCaseJob }
    end
  end

  def run_with_case(actual_json)
    run = EvaluationRun.create!(
      user: @user, dataset_name: "m.csv", dataset_version: "v1",
      provider: "openrouter", model: "m", status: "completed", total_cases: 1
    )
    case_record = run.evaluation_cases.create!(
      row_number: 1, message: "pedimos por rappi hoy",
      expected_json: { "category" => "Comida y restaurantes" },
      actual_json: actual_json, status: "failed"
    )
    [ run, case_record ]
  end

  test "POST mapping with accept_received records the user decision for the activity" do
    category = Category.create!(name: "Comida y restaurantes", user: @user, is_default: false)
    run, case_record = run_with_case("activity" => "Restaurante (Rappi)", "category" => "Comida y restaurantes")

    post expense_evaluation_map_case_path(run, case_record, format: :json),
         params: { mapping_action: "accept_received" }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["ok"]
    assert_equal true, data["mapped"]
    assert_equal "Comida y restaurantes", data["category"]
    learned = ActivityClassification.lookup(user: @user, name: "Restaurante (Rappi)")
    assert_equal category.id, learned.category_id
  end

  test "POST mapping with use_existing binds the case activity to the chosen category" do
    category = Category.create!(name: "Entretenimiento", user: @user, is_default: false)
    run, case_record = run_with_case("activity" => "Pago de Netflix", "category" => "Entretenimiento")

    post expense_evaluation_map_case_path(run, case_record, format: :json),
         params: { mapping_action: "use_existing", category_id: category.id }

    assert_response :success
    learned = ActivityClassification.lookup(user: @user, name: "Pago de Netflix")
    assert_equal category.id, learned.category_id
  end

  test "POST mapping with create folds near-duplicate names into an existing category" do
    existing = Category.create!(name: "Comida y restaurantes", user: @user, is_default: false)
    run, case_record = run_with_case("activity" => "Pedido Rappi", "category" => "Restaurante (Rappi)")

    assert_no_difference "Category.count" do
      post expense_evaluation_map_case_path(run, case_record, format: :json),
           params: { mapping_action: "create", new_category_name: "Restaurante (Rappi)" }
    end

    assert_response :success
    assert_equal "Comida y restaurantes", JSON.parse(response.body)["category"]
    assert_equal existing.id, ActivityClassification.lookup(user: @user, name: "Pedido Rappi").category_id
  end

  test "POST mapping with create makes a genuinely-new category" do
    run, case_record = run_with_case("activity" => "Suscripcion Mensual", "category" => "Suscripciones")

    assert_difference "Category.count" => 1 do
      post expense_evaluation_map_case_path(run, case_record, format: :json),
           params: { mapping_action: "create", new_category_name: "Suscripciones" }
    end

    assert_response :success
    assert_equal "Suscripciones", JSON.parse(response.body)["category"]
  end

  test "POST mapping requires an existing category when using use_existing" do
    run, case_record = run_with_case("activity" => "Netflix", "category" => "Entretenimiento")

    post expense_evaluation_map_case_path(run, case_record, format: :json),
         params: { mapping_action: "use_existing", category_id: 999_999 }

    assert_response :not_found
  end

  test "POST mapping does not touch another user's run or case" do
    stranger = User.create!(name: "Stranger", email: "pg-stranger-#{SecureRandom.hex(6)}@example.com", password: "password123")
    other_run = EvaluationRun.create!(
      user: stranger, dataset_name: "x.csv", dataset_version: "v1",
      provider: "openrouter", model: "m", status: "completed", total_cases: 1
    )
    other_case = other_run.evaluation_cases.create!(
      row_number: 1, message: "compra", expected_json: {}, actual_json: { "activity" => "Compra", "category" => "Compras" }, status: "failed"
    )

    post expense_evaluation_map_case_path(other_run, other_case, format: :json),
         params: { mapping_action: "accept_received" }

    assert_response :not_found
  end

  test "cases list exposes mapped and suggested_category for the review table" do
    existing = Category.create!(name: "Comida y restaurantes", user: @user, is_default: false)
    run, case_record = run_with_case("activity" => "Pedido Rappi", "category" => "Restaurante (Rappi)")

    get expense_evaluation_cases_path(run, format: :json, status: "failed")

    assert_response :success
    entry = JSON.parse(response.body)["cases"].first
    assert_equal false, entry["mapped"]
    assert_equal "Comida y restaurantes", entry["suggested_category"]

    post expense_evaluation_map_case_path(run, case_record, format: :json),
         params: { mapping_action: "accept_received" }
    get expense_evaluation_cases_path(run, format: :json, status: "failed")

    assert_equal true, JSON.parse(response.body)["cases"].first["mapped"]
    assert_equal existing.id, existing.id
  end
end

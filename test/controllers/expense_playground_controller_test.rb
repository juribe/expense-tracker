# frozen_string_literal: true

require "test_helper"

class ExpensePlaygroundControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Playground Controller User", email: "pg-controller@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    sign_in @user
    @saved_api_key = ENV.delete("MISTRAL_API_KEY")
  end

  teardown do
    ENV["MISTRAL_API_KEY"] = @saved_api_key
  end

  test "GET /expense-playground requires authentication" do
    sign_out :user
    get expense_playground_path
    assert_response :redirect
  end

  test "GET /expense-playground renders the page for signed-in users" do
    get expense_playground_path
    assert_response :success
    assert_match "Expense Playground", response.body
  end

  test "POST /expense-playground/process returns a candidate without persisting any expense" do
    assert_no_difference -> { Expense.count } do
      assert_no_difference -> { Category.count } do
        post expense_playground_process_path(format: :json),
             params: { type: "text", text: "Me gasté 50mil en almuerzos" }
      end
    end

    assert_response :success
    data = JSON.parse(response.body)

    assert data["ok"]
    candidate = data["candidate"]
    assert_equal 50_000.0, candidate["amount"].to_f
    assert_equal "COP", candidate["currency"]
    assert_equal @restaurants.id, candidate["category_id"]
    assert_equal "playground", candidate["source"]
    assert data["steps"].key?("input")
    assert data["steps"].key?("ocr")
    assert data["steps"].key?("extraction")
    assert data["steps"].key?("normalization")
    assert data["steps"].key?("validation")
    assert data["duration_ms"].is_a?(Integer)

    # The execution itself is recorded for history (but no expense).
    assert_equal 1, @user.expense_playground_runs.count
    run = @user.expense_playground_runs.recent_first.first
    assert run.ok?
    assert data["run_id"] == run.id
    assert_nil run.expense_id
  end

  test "POST /expense-playground/process evaluates against expected results" do
    post expense_playground_process_path(format: :json), params: {
      type: "text",
      text: "Me gasté 50mil en almuerzos",
      expected: { amount: "50000", category: "restaurants", description: "gasolina" }
    }

    assert_response :success
    evaluation = JSON.parse(response.body)["evaluation"]
    assert_equal 2, evaluation["passed"]
    assert_equal 3, evaluation["total"]
    fields = evaluation["checks"].map { |check| check["field"] }
    assert_equal %w[amount category description], fields
  end

  test "POST /expense-playground/process omits the evaluation when no expectations are given" do
    post expense_playground_process_path(format: :json),
         params: { type: "text", text: "Me gasté 50mil en almuerzos" }
    assert_nil JSON.parse(response.body)["evaluation"]
  end

  test "GET /expense-playground/history returns only the current user's runs" do
    ExpensePlaygroundRun.create!(user: @user, input_type: "text", status: "ok",
      candidate: { "amount" => 50_000, "confidence" => 0.9 }, steps: { input: { type: "text" } })

    other = User.create!(name: "Other", email: "other-hist@example.com", password: "password123")
    ExpensePlaygroundRun.create!(user: other, input_type: "image", status: "failed",
      candidate: {}, steps: {})

    get expense_playground_history_path(format: :json)
    assert_response :success

    runs = JSON.parse(response.body)["runs"]
    assert_equal 1, runs.length
    assert_equal "text", runs.first["type"]
  end

  test "POST /expense-playground/create links the created expense to the run" do
    run = ExpensePlaygroundRun.create!(user: @user, input_type: "text", status: "ok",
      candidate: { "amount" => 50_000, "category_name" => "Restaurants" }, steps: { input: { type: "text" } })

    post expense_playground_create_path(format: :json), params: {
      run_id: run.id,
      candidate: {
        amount: "50000",
        category_id: @restaurants.id,
        description: "Almuerzos",
        date: Date.current.iso8601,
        source: "playground"
      }
    }

    assert_response :created
    assert_equal Expense.find(JSON.parse(response.body)["expense_id"]).id, run.reload.expense_id
  end

  test "POST /expense-playground/create ignores run ids owned by other users" do
    other = User.create!(name: "Other", email: "other-link@example.com", password: "password123")
    foreign_run = ExpensePlaygroundRun.create!(user: other, input_type: "text", status: "ok",
      candidate: {}, steps: {})

    post expense_playground_create_path(format: :json), params: {
      run_id: foreign_run.id,
      candidate: {
        amount: "50000",
        category_id: @restaurants.id,
        date: Date.current.iso8601,
        source: "playground"
      }
    }

    assert_response :created
    assert_nil foreign_run.reload.expense_id
  end

  test "POST /expense-playground/process rejects blank input" do
    post expense_playground_process_path(format: :json), params: { type: "text", text: "" }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "POST /expense-playground/process validates image inputs" do
    post expense_playground_process_path(format: :json),
         params: { type: "image", image_data: "data:text/html;base64,PGI+" }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "POST /expense-playground/create persists the reviewed candidate through Expenses::Create" do
    assert_difference -> { Expense.count }, 1 do
      post expense_playground_create_path(format: :json), params: {
        candidate: {
          amount: "50000",
          currency: "COP",
          category_id: @restaurants.id,
          description: "Almuerzos",
          merchant: "",
          date: Date.current.iso8601,
          source: "playground",
          confidence: 0.94
        }
      }
    end

    assert_response :created
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal @user.id, Expense.find(data["expense_id"]).user_id

    expense = Expense.find(data["expense_id"])
    assert_equal BigDecimal(50_000.to_s), expense.amount.abs
    assert_equal "playground", expense.source
    assert_equal @restaurants.id, expense.category_id
  end

  test "POST /expense-playground/create with an edited candidate creates a new category when needed" do
    assert_difference -> { Expense.count }, 1 do
      assert_difference -> { Category.count }, 1 do
        post expense_playground_create_path(format: :json), params: {
          candidate: {
            amount: "29900",
            category_id: "",
            category_name: "Streaming",
            description: "Netflix",
            date: Date.current.iso8601,
            source: "playground"
          }
        }
      end
    end

    assert_response :created
    expense = Expense.find(JSON.parse(response.body)["expense_id"])
    assert_equal "Streaming", expense.category.name
    assert_equal @user.id, expense.category.user_id
  end

  test "POST /expense-playground/create revalidates the candidate" do
    assert_no_difference -> { Expense.count } do
      post expense_playground_create_path(format: :json), params: {
        candidate: { amount: "", category_id: @restaurants.id, date: Date.current.iso8601 }
      }
    end

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "POST /expense-playground/create rejects categories owned by other users" do
    other_user = User.create!(name: "Other", email: "other@example.com", password: "password123")
    foreign_category = Category.create!(name: "Foreign", user: other_user, is_default: false, category_type: "expense")

    assert_no_difference -> { Expense.count } do
      post expense_playground_create_path(format: :json), params: {
        candidate: {
          amount: "1000",
          category_id: foreign_category.id,
          date: Date.current.iso8601
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST /expense-playground/process detects the money source in the candidate" do
    source = MoneySource.create!(user: @user, name: "Nequi", kind: "wallet", starting_balance: 100_000)

    post expense_playground_process_path(format: :json),
         params: { type: "text", text: "Me gasté 50 mil en almuerzo desde nequi" }

    assert_response :success
    candidate = JSON.parse(response.body)["candidate"]
    assert_equal source.id, candidate["money_source_id"]
    assert_equal "Nequi", candidate["money_source_name"]
    assert_equal "Nequi", JSON.parse(response.body)["steps"]["normalization"]["money_source_name"]
  end

  test "POST /expense-playground/create persists the detected money source" do
    source = MoneySource.create!(user: @user, name: "Nequi", kind: "wallet", starting_balance: 100_000)

    post expense_playground_create_path(format: :json), params: {
      candidate: {
        amount: "50000",
        currency: "COP",
        category_id: @restaurants.id,
        date: Date.current.iso8601,
        source: "playground",
        money_source_id: source.id,
        money_source_name: "Nequi"
      }
    }

    assert_response :created
    expense = Expense.find(JSON.parse(response.body)["expense_id"])
    assert_equal source.id, expense.money_source_id
  end

  test "POST /expense-playground/create rejects money sources owned by other users" do
    other_user = User.create!(name: "Other MS", email: "other-ms@example.com", password: "password123")
    foreign_source = MoneySource.create!(user: other_user, name: "Foreign", kind: "wallet", starting_balance: 1)

    assert_no_difference -> { Expense.count } do
      post expense_playground_create_path(format: :json), params: {
        candidate: {
          amount: "1000",
          category_id: @restaurants.id,
          date: Date.current.iso8601,
          money_source_id: foreign_source.id
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "POST /expense-playground/process and create require authentication" do
    sign_out :user
    post expense_playground_process_path, params: { type: "text", text: "hola" }
    assert_response :redirect

    post expense_playground_create_path, params: { candidate: { amount: "1000" } }
    assert_response :redirect
  end

  test "GET /expense-playground renders the file upload tab" do
    get expense_playground_path
    assert_response :success
    assert_match "tab-file", response.body
    assert_match "playground-file-dropzone", response.body
    assert_match "playground-pdf-password", response.body
  end

  test "POST /expense-playground/process_file rejects an unsupported file type" do
    post expense_playground_process_file_path(format: :json),
         params: { file_data: "data:text/plain;base64,", filename: "notes.txt", password: nil }

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_not data["ok"]
    assert data["errors"].any?
  end

  test "POST /expense-playground/process_file extracts transactions from a CSV deterministically" do
    csv = "Fecha,Descripcion,Valor\n2026-09-09,DIDI FOOD,45000\n2026-09-08,UBER,22000\n"
    file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

    post expense_playground_process_file_path(format: :json),
         params: { file_data: file_data, filename: "stmt.csv", password: nil }

    assert_response :success
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal "deterministic", data["steps"]["engine"]
    assert_equal 2, data["candidates"].length
    assert_equal "DIDI FOOD", data["candidates"].first["description"]
    assert_equal 45_000.0, data["candidates"].first["amount"].to_f
  end

  test "POST /expense-playground/batch_create creates every reviewed candidate and reports failures" do
    assert_difference -> { Expense.count }, 2 do
      assert_no_difference -> { Category.count } do
        post expense_playground_batch_create_path(format: :json), params: {
          candidates: [
            { amount: "45000", category_id: @restaurants.id, description: "DIDI FOOD", date: Date.current.iso8601 },
            { amount: "183450", category_id: @restaurants.id, description: "EXITO", date: Date.current.iso8601 },
            { amount: "", category_id: @restaurants.id, description: "BAD ROW", date: Date.current.iso8601 }
          ]
        }
      end
    end

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal 2, data["created"].length
    assert_equal 1, data["errors"].length
    assert_equal "playground_file", Expense.last.source
  end

  test "POST /expense-playground/process_file flags duplicates within the batch" do
    csv = "Fecha,Descripcion,Valor\n2026-09-09,DIDI FOOD,45000\n2026-09-09,DIDI FOOD,45000\n2026-09-08,UBER,22000\n"
    file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

    post expense_playground_process_file_path(format: :json),
         params: { file_data: file_data, filename: "stmt.csv", password: nil }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal [ 1 ], data["duplicates"]
    assert_equal false, data["candidates"][0]["duplicate"]
    assert_equal true, data["candidates"][1]["duplicate"]
    assert_equal false, data["candidates"][2]["duplicate"]
  end

  test "POST /expense-playground/process_file reports enrichment sources for auditability" do
    csv = "Fecha,Descripcion,Valor\n2026-09-09,DIDI FOOD,45000\n"
    file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

    post expense_playground_process_file_path(format: :json),
         params: { file_data: file_data, filename: "stmt.csv", password: nil }

    assert_response :success
    candidate = JSON.parse(response.body)["candidates"].first
    assert_equal "fallback", candidate["classification_source"]
    assert_equal "missing", candidate["money_source_source"]
  end

  test "POST /expense-playground/process_file reuses a stored classification instead of guessing" do
    food = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: food, source: "ai")

    csv = "Fecha,Descripcion,Valor\n2026-09-09,DIDI FOOD,45000\n"
    file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

    post expense_playground_process_file_path(format: :json),
         params: { file_data: file_data, filename: "stmt.csv", password: nil }

    assert_response :success
    candidate = JSON.parse(response.body)["candidates"].first
    assert_equal "cached_ai", candidate["classification_source"]
    assert_equal "Comida", candidate["category_name"]
  end

  test "POST /expense-playground/batch_create records a user category correction as knowledge" do
    assert_difference -> { ActivityClassification.count }, 1 do
      post expense_playground_batch_create_path(format: :json), params: {
        candidates: [
          {
            amount: "45000",
            category_id: @restaurants.id,
            description: "DIDI FOOD",
            date: Date.current.iso8601,
            classification_source: "ai",
            suggested_category_name: "Comida y restaurantes"
          }
        ]
      }
    end

    assert_response :success
    classification = ActivityClassification.lookup(user: @user, name: "DIDI FOOD")
    assert_equal "user", classification.source
    assert_equal @restaurants, classification.category
  end
end

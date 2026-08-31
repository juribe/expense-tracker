# frozen_string_literal: true

require "test_helper"

class FinancialSetupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "financial_setup_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  def setup_record
    @setup = @user.financial_setups.create!(status: "in_progress")
  end

  def successful_pipeline
    result = ImportPipeline::Result.new(
      ok?: true,
      sources: [ ParsedStatement.new(kind: "account", name: "Bancolombia Savings", bank: "Bancolombia", balance: "5420000") ],
      transactions: [ { date: "2026-08-01", description: "Market", amount: -10_000, type: "expense" } ],
      error: nil
    )
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |file:, password: nil| result }
    pipeline
  end

  def upload_file(name = "statement.csv")
    file = Tempfile.new(File.basename(name))
    file.write("a,b\n1,2\n")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: name)
  end

  # ----------------------------------------------------------- entry / steps

  test "redirects unauthenticated users to sign in" do
    sign_out @user
    get financial_setup_path
    assert_redirected_to new_user_session_path
  end

  test "GET /financial_setup renders the entry screen" do
    get financial_setup_path
    assert_response :success
    assert_select "h2", text: I18n.t("wizard.entry.title")
  end

  test "GET /financial_setup resumes at the last incomplete step" do
    setup_record
    @setup.set_choice("accounts", "skip")
    @setup.current_step = 1
    @setup.save!

    get financial_setup_path
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
  end

  test "GET /financial_setup redirects to done when already completed" do
    setup_record
    @setup.complete!
    get financial_setup_path
    assert_redirected_to financial_setup_done_path
  end

  test "renders each wizard step" do
    FinancialSetupWizard.step_keys.each do |step_key|
      get financial_setup_step_path(step: step_key)
      assert_response :success, "expected #{step_key} to render"
    end
  end

  test "redirects an unknown step to the entry screen" do
    get financial_setup_step_path(step: :wallet)
    assert_redirected_to financial_setup_path
  end

  # ----------------------------------------------------------- select choice

  test "POST select with skip records the choice and advances" do
    setup_record
    post financial_setup_select_path, params: { step: "accounts", choice: "skip" }
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
    assert_equal "skip", @setup.reload.choice_for("accounts")
    assert_equal 1, @setup.current_step
  end

  test "POST select with manual routes to the manual screen" do
    setup_record
    post financial_setup_select_path, params: { step: "accounts", choice: "manual" }
    assert_redirected_to financial_setup_manual_screen_path(step: :accounts)
    assert_equal "manual", @setup.reload.choice_for("accounts")
  end

  test "POST select with import routes to the upload screen" do
    setup_record
    post financial_setup_select_path, params: { step: "loans", choice: "import" }
    assert_redirected_to financial_setup_upload_screen_path(step: :loans)
    assert_equal "import", @setup.reload.choice_for("loans")
  end

  test "POST select with an invalid choice redirects back with an alert" do
    setup_record
    post financial_setup_select_path, params: { step: "accounts", choice: "export" }
    assert_redirected_to financial_setup_step_path(step: :accounts)
    assert_match(/válida/i, flash[:alert])
    assert_nil @setup.reload.choice_for("accounts")
  end

  test "POST select advances through the final source step to review" do
    setup_record
    post financial_setup_select_path, params: { step: "loans", choice: "skip" }
    assert_redirected_to financial_setup_step_path(step: :review)
    assert_equal 3, @setup.reload.current_step
  end

  # ----------------------------------------------------------- manual entry

  test "GET manual renders a blank draft row" do
    get financial_setup_manual_screen_path(step: :accounts)
    assert_response :success
    assert_select "input[name='sources[0][name]']"
  end

  test "POST manual saves draft rows and advances" do
    setup_record
    post financial_setup_manual_path, params: {
      step: "accounts",
      sources: {
        "0" => { name: "Savings", bank: "Bancolombia", balance: "5420000" },
        "1" => { name: "Checking", bank: "Davivienda", balance: "2180000" }
      }
    }
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
    rows = @setup.reload.draft_sources("accounts")
    assert_equal 2, rows.length
    assert_equal "Savings", rows.first["name"]
    assert_equal "manual", @setup.choice_for("accounts")
  end

  test "POST manual accepts array-shaped sources" do
    setup_record
    post financial_setup_manual_path, params: {
      step: "accounts",
      sources: [ { name: "Savings", bank: "Bancolombia", balance: "5420000" } ]
    }
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
    assert_equal [ "Savings" ], @setup.reload.draft_sources("accounts").map { |row| row["name"] }
  end

  # ----------------------------------------------------------- upload/import

  test "GET upload renders the dropzone" do
    setup_record
    get financial_setup_upload_screen_path(step: :accounts)
    assert_response :success
    assert_select "input[type='file']"
    assert_equal "import", @setup.reload.choice_for("accounts")
  end

  test "POST upload requires a file" do
    setup_record
    post financial_setup_upload_path, params: { step: "accounts" }
    assert_response :success
    assert_match(/archivo/i, response.body)
  end

  test "POST upload rejects unsupported file types" do
    setup_record
    post financial_setup_upload_path, params: { step: "accounts", file: upload_file("note.txt") }
    assert_response :success
    assert_match(/Unsupported file type/i, response.body)
  end

  test "POST upload stores the extraction and routes to review" do
    setup_record
    pipeline = successful_pipeline
    stub_method(ImportPipeline, :new, ->(*) { pipeline }) do
      post financial_setup_upload_path, params: { step: "accounts", file: upload_file("statement.csv") }
      assert_redirected_to financial_setup_import_review_path(step: :accounts)

      import = @setup.reload.import_state("accounts")
      assert_equal "Bancolombia Savings", import["sources"].first["name"]
      assert_equal "import", @setup.choice_for("accounts")
      assert_equal "Bancolombia Savings", @setup.draft_sources("accounts").first["name"]
    end
  end

  test "GET import_review shows extracted sources" do
    get financial_setup_import_review_path(step: :accounts)
    assert_response :success
  end

  test "GET import_review renders extracted sources, duplicate choice and transactions" do
    setup_record
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "transactions" => [ { "date" => "2026-08-01", "description" => "Market", "amount" => "10000", "type" => "expense" } ],
      "duplicates" => { "1234" => { "choice" => "update", "duplicate" => true } }
    })
    @setup.save!

    get financial_setup_import_review_path(step: :accounts)
    assert_response :success
    assert_select "h3", text: I18n.t("wizard.review_extract.title", count: 1, noun: I18n.t("wizard.review.accounts", count: 1).downcase)
    assert_select "input[name='duplicates[1234]'][value='update'][checked='checked']"
    assert_match(/Market/, response.body)
    assert_match(/Bancolombia Savings/, response.body)
  end

  test "POST import_confirm drops unchecked sources" do
    setup_record
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia", "kind" => "account", "balance" => "5420000" },
        { "identifier" => "8976", "name" => "Davivienda Savings", "bank" => "Davivienda", "kind" => "account", "balance" => "2180000" }
      ],
      "duplicates" => { "1234" => { "choice" => "create" }, "8976" => { "choice" => "create" } }
    })
    @setup.save!

    post financial_setup_import_confirm_path, params: { step: "accounts", keep: { "0" => "1" } }
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
    sources = @setup.reload.import_state("accounts")["sources"]
    assert_equal 1, sources.length
    assert_equal "Bancolombia Savings", sources.first["name"]
  end

  test "POST import_confirm merges inline edits" do
    setup_record
    @setup.set_import_state("accounts", {
      "sources" => [ { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia", "kind" => "account", "balance" => "5420000" } ],
      "duplicates" => { "1234" => { "choice" => "create" } }
    })
    @setup.save!

    post financial_setup_import_confirm_path, params: {
      step: "accounts",
      sources: { "0" => { name: "Bancolombia Ahorros", bank: "Bancolombia", balance: "1000000" } }
    }
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
    source = @setup.reload.import_state("accounts")["sources"].first
    assert_equal "Bancolombia Ahorros", source["name"]
    assert_equal "1000000", source["balance"]
  end

  # ----------------------------------------------------------- completion

  test "POST complete creates records and shows the done screen" do
    setup_record
    @setup.set_choice("accounts", "manual")
    @setup.replace_draft_sources("accounts", [ { "name" => "Savings", "bank" => "Bancolombia", "balance" => "5420000" } ])
    @setup.save!

    assert_difference "MoneySource.count", 1 do
      post financial_setup_complete_path
    end
    assert_redirected_to financial_setup_done_path
    assert @setup.reload.completed?
  end

  test "GET done renders the success screen after completion" do
    setup_record
    post financial_setup_complete_path
    get financial_setup_done_path
    assert_response :success
    assert_select "h3", text: I18n.t("wizard.done.title")
  end

  test "GET done redirects to the wizard when not completed" do
    get financial_setup_done_path
    assert_redirected_to financial_setup_path
  end

  test "GET review summarizes the configured sources" do
    setup_record
    @setup.set_choice("accounts", "manual")
    @setup.replace_draft_sources("accounts", [ { "name" => "Bancolombia Savings", "bank" => "Bancolombia", "balance" => "5420000" } ])
    @setup.set_choice("credit_cards", "skip")
    @setup.save!

    get financial_setup_step_path(step: :review)
    assert_response :success
    assert_match(/Bancolombia Savings/, response.body)
    assert_match(/1 fuente financiera configurada/, response.body)
  end

  test "POST dismiss marks the setup dismissed and keeps progress" do
    setup_record
    @setup.set_choice("accounts", "manual")
    @setup.save!

    post financial_setup_dismiss_path
    assert_redirected_to dashboard_path
    assert @setup.reload.dismissed?
    assert_equal "manual", @setup.choice_for("accounts")
  end
end

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
    assert_redirected_to financial_setup_step_path(step: :accounts)
  end

  test "GET /financial_setup redirects to done when already completed" do
    setup_record
    @setup.complete!
    get financial_setup_path
    assert_redirected_to financial_setup_done_path
  end

  test "setup wizard link is shown in the sidebar when setup is not completed" do
    get financial_setup_path
    assert_response :success
    assert_match(/#{I18n.t("nav.setup_wizard")}/, response.body)
  end

  test "setup wizard link is hidden in the sidebar once setup is completed" do
    setup_record
    @setup.complete!
    get money_sources_cash_path
    assert_response :success
    assert_no_match(/#{I18n.t("nav.setup_wizard")}/, response.body)
    assert_match(/#{I18n.t("nav.money_sources_cash")}/, response.body)
  end

  test "renders each wizard step" do
    FinancialSetupWizard.step_keys.each do |step_key|
      get financial_setup_step_path(step: step_key)
      assert_response :success, "expected #{step_key} to render"
    end
  end

  test "step screen shows continue option when sources were added" do
    setup_record
    @setup.set_choice("loans", "import")
    @setup.set_import_state("loans", {
      "sources" => [
        { "identifier" => "1111", "name" => "Vehículo", "bank" => "Banco", "kind" => "loan", "outstanding_balance" => "1000" },
        { "identifier" => "2222", "name" => "Hipotecario", "bank" => "Banco", "kind" => "loan", "outstanding_balance" => "2000" },
        { "identifier" => "3333", "name" => "Rotativo", "bank" => "Banco", "kind" => "loan", "outstanding_balance" => "3000" }
      ],
      "duplicates" => {}
    })
    @setup.save!

    get financial_setup_step_path(step: :loans)
    assert_response :success
    assert_match(I18n.t("wizard.select.continue_title"), response.body)
    assert_match(/3/, response.body)
  end

  test "step screen counts deduplicated sources when an import duplicates an added account" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.replace_draft_sources("accounts", [
      { "identifier" => "5986", "name" => "Cuenta de Ahorros", "bank" => "Bancolombia", "kind" => "account", "balance" => "608" }
    ])
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "5986", "name" => "Cuenta de Ahorros", "bank" => "Bancolombia", "kind" => "account", "balance" => "608" },
        { "identifier" => "8901", "name" => "Ahorros Davibank", "bank" => "Davibank", "kind" => "account", "balance" => "500000" }
      ],
      "duplicates" => {}
    })
    @setup.save!

    get financial_setup_step_path(step: :accounts)
    assert_response :success
    # 3 raw rows across stores, but only 2 unique accounts.
    assert_match(I18n.t("wizard.select.added", count: 2), response.body)
    assert_match(/2 cuentas/, response.body)
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
    assert_equal 2, @setup.current_step
  end

  test "POST select with skip keeps the existing choice when the step has sources" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "5986", "name" => "Cuenta de Ahorros", "bank" => "Bancolombia", "kind" => "account", "balance" => "608" }
      ],
      "duplicates" => {}
    })
    @setup.save!

    # The third card reads "Continuar" when sources exist — it must not clobber
    # the import choice, or completion would skip the step.
    post financial_setup_select_path, params: { step: "accounts", choice: "skip" }
    assert_redirected_to financial_setup_step_path(step: :credit_cards)
    assert_equal "import", @setup.reload.choice_for("accounts")
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
    assert_equal 4, @setup.reload.current_step
  end

  # ----------------------------------------------------------- manual entry

  test "GET manual renders a blank draft row" do
    get financial_setup_manual_screen_path(step: :accounts)
    assert_response :success
    assert_select "input[name='sources[0][name]']"
  end

  test "GET manual for cash renders the cash balance field" do
    get financial_setup_manual_screen_path(step: :cash)
    assert_response :success
    assert_select "input[name='sources[0][balance]']"
  end

  test "GET manual for cash hides the bank field" do
    get financial_setup_manual_screen_path(step: :cash)
    assert_response :success
    assert_select "input[name='sources[0][bank]']", count: 0
  end

  test "cash step does not offer the import option" do
    setup_record
    get financial_setup_step_path(step: :cash)
    assert_response :success
    assert_select "input[name='choice'][value='import']", count: 0
    assert_select "input[name='choice'][value='manual']", count: 1
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
    assert_match(I18n.t("wizard.upload.unsupported_type"), response.body)
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
      assert_empty @setup.draft_sources("accounts")
    end
  end

  test "GET import_review shows extracted sources" do
    get financial_setup_import_review_path(step: :accounts)
    assert_response :success
  end

  test "POST upload drops sources whose kind does not match the step" do
    setup_record
    result = ImportPipeline::Result.new(
      ok?: true,
      sources: [ ParsedStatement.new(kind: "credit_card", name: "Crédito Rotativo", bank: "Davibank", balance: "19877599") ],
      transactions: [],
      error: nil
    )
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |file:, password: nil| result }

    stub_method(ImportPipeline, :new, ->(*) { pipeline }) do
      post financial_setup_upload_path, params: { step: "loans", file: upload_file("statement.csv") }
      assert_redirected_to financial_setup_import_review_path(step: :loans)
      assert_empty @setup.reload.import_state("loans")["sources"]
      assert_match(/omit/i, flash[:alert])
    end
  end

  test "POST upload keeps every source extracted from one document" do
    setup_record
    result = ImportPipeline::Result.new(
      ok?: true,
      sources: [
        ParsedStatement.new(kind: "account", name: "Ahorros", bank: "Bancolombia", balance: "1000000", identifier: "1111"),
        ParsedStatement.new(kind: "account", name: "Corriente", bank: "Bancolombia", balance: "2000000", identifier: "2222")
      ],
      transactions: [],
      error: nil
    )
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |file:, password: nil| result }

    stub_method(ImportPipeline, :new, ->(*) { pipeline }) do
      post financial_setup_upload_path, params: { step: "accounts", file: upload_file("statement.csv") }
      assert_redirected_to financial_setup_import_review_path(step: :accounts)
      names = @setup.reload.import_state("accounts")["sources"].map { |s| s["name"] }
      assert_equal %w[Ahorros Corriente], names.sort
    end
  end

  test "POST upload shows the newest imported sources first" do
    setup_record
    first_result = ImportPipeline::Result.new(
      ok?: true,
      sources: [ ParsedStatement.new(kind: "account", name: "Ahorros", bank: "Bancolombia", balance: "1000000", identifier: "1111") ],
      transactions: [], error: nil
    )
    first_pipeline = Object.new
    first_pipeline.define_singleton_method(:call) { |file:, password: nil| first_result }

    second_result = ImportPipeline::Result.new(
      ok?: true,
      sources: [ ParsedStatement.new(kind: "account", name: "Corriente", bank: "Davivienda", balance: "2000000", identifier: "2222") ],
      transactions: [], error: nil
    )
    second_pipeline = Object.new
    second_pipeline.define_singleton_method(:call) { |file:, password: nil| second_result }

    stub_method(ImportPipeline, :new, ->(*) { first_pipeline }) do
      post financial_setup_upload_path, params: { step: "accounts", file: upload_file("statement.csv") }
      assert_redirected_to financial_setup_import_review_path(step: :accounts)
    end
    stub_method(ImportPipeline, :new, ->(*) { second_pipeline }) do
      post financial_setup_upload_path, params: { step: "accounts", file: upload_file("other.csv") }
      assert_redirected_to financial_setup_import_review_path(step: :accounts)
    end

    names = @setup.reload.import_state("accounts")["sources"].map { |s| s["name"] }
    assert_equal %w[Corriente Ahorros], names
    # The import review renders in stored order, so the newest is on top there too.
    get financial_setup_import_review_path(step: :accounts)
    assert_match(/Corriente/, response.body)
  end

  test "GET import_review renders extracted sources and duplicate choice" do
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
    assert_select "h1", text: I18n.t("wizard.review_extract.page_title.account", count: 1)
    assert_select "input[name='duplicates[1234]'][value='update'][checked='checked']"
    assert_match(/Bancolombia Savings/, response.body)
  end

  test "GET import_review renders all editable loan fields" do
    setup_record
    @setup.set_import_state("loans", {
      "sources" => [
        { "identifier" => "987654321", "name" => "Car Loan", "bank" => "Banco", "kind" => "loan",
          "outstanding_balance" => "95000000", "principal_amount" => "100000000",
          "monthly_payment" => "2686800", "installment_count" => "48", "installments_paid" => "12",
          "interest_rate" => "21.27", "interest_rate_type" => "effective_annual" }
      ],
      "duplicates" => {}
    })
    @setup.save!

    get financial_setup_import_review_path(step: :loans)
    assert_response :success
    assert_select "input[name='sources[0][outstanding_balance]']"
    assert_select "input[name='sources[0][principal_amount]'][value='100.000.000']"
    assert_select "input[name='sources[0][monthly_payment]'][value='2.686.800']"
    assert_select "input[name='sources[0][installment_count]'][value='48']"
    assert_select "input[name='sources[0][installments_paid]'][value='12']"
    assert_select "input[name='sources[0][interest_rate]'][value='21,27']"
    assert_select "select[name='sources[0][interest_rate_type]']"
    # Loan identifiers are reduced to last four digits for privacy.
    assert_select "input[name='sources[0][identifier]'][value='4321']"
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

  test "POST import_confirm merges manual-size credit card fields" do
    setup_record
    @setup.set_import_state("credit_cards", {
      "sources" => [
        { "identifier" => "8976", "name" => "Visa", "bank" => "Davivienda", "kind" => "credit_card",
          "balance" => "2180000", "credit_limit" => "10000000", "card_last_four" => "8976",
          "interest_rate" => "18", "interest_rate_type" => "effective_annual" }
      ],
      "duplicates" => { "8976" => { "choice" => "create" } }
    })
    @setup.save!

    post financial_setup_import_confirm_path, params: {
      step: "credit_cards",
      sources: { "0" => { name: "Visa Platino", bank: "Davivienda", balance: "1500000",
                          credit_limit: "12000000", interest_rate: "20", interest_rate_type: "monthly" } }
    }
    assert_redirected_to financial_setup_step_path(step: :loans)
    source = @setup.reload.import_state("credit_cards")["sources"].first
    assert_equal "Visa Platino", source["name"]
    assert_equal "1500000", source["balance"]
    assert_equal "12000000", source["credit_limit"]
    assert_equal "20", source["interest_rate"]
    assert_equal "monthly", source["interest_rate_type"]
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

  test "POST import_confirm normalizes Colombian-formatted money values" do
    setup_record
    @setup.set_import_state("credit_cards", {
      "sources" => [ { "identifier" => "6017", "name" => "Visa", "bank" => "Davivienda", "kind" => "credit_card",
                       "balance" => "57349802", "credit_limit" => "57405600" } ],
      "duplicates" => { "6017" => { "choice" => "create" } }
    })
    @setup.save!

    post financial_setup_import_confirm_path, params: {
      step: "credit_cards",
      sources: { "0" => { name: "Visa", bank: "Davivienda", balance: "57.349.802",
                          credit_limit: "57.405.600,50", interest_rate: "29,3" } }
    }

    source = @setup.reload.import_state("credit_cards")["sources"].first
    assert_equal "57349802", source["balance"]
    assert_equal "57405600.50", source["credit_limit"]
    assert_equal "29.3", source["interest_rate"]
  end

  test "POST import_confirm keeps decimals from the browser machine format" do
    # The input mask submits "972548.58" (dot as decimal). The server must not
    # treat that dot as a thousands separator (regression: saved 97254858).
    setup_record
    @setup.set_import_state("accounts", {
      "sources" => [ { "identifier" => "1234", "name" => "Ahorros", "bank" => "Bancolombia", "kind" => "account", "balance" => "0" } ],
      "duplicates" => { "1234" => { "choice" => "create" } }
    })
    @setup.save!

    post financial_setup_import_confirm_path, params: {
      step: "accounts",
      sources: { "0" => { name: "Ahorros", bank: "Bancolombia", balance: "972548.58" } }
    }

    source = @setup.reload.import_state("accounts")["sources"].first
    assert_equal "972548.58", source["balance"]
  end

  test "POST import_confirm strips thousands from dot-grouped display values" do
    setup_record
    @setup.set_import_state("accounts", {
      "sources" => [ { "identifier" => "1234", "name" => "Ahorros", "bank" => "Bancolombia", "kind" => "account", "balance" => "0" } ],
      "duplicates" => { "1234" => { "choice" => "create" } }
    })
    @setup.save!

    post financial_setup_import_confirm_path, params: {
      step: "accounts",
      sources: { "0" => { name: "Ahorros", bank: "Bancolombia", balance: "97.254.852" } }
    }

    source = @setup.reload.import_state("accounts")["sources"].first
    assert_equal "97254852", source["balance"]
  end

  test "POST import_confirm with save_only keeps the same step" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.set_import_state("accounts", {
      "sources" => [ { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia", "kind" => "account", "balance" => "5420000" } ],
      "duplicates" => { "1234" => { "choice" => "create" } }
    })
    @setup.save!
    current = @setup.current_step

    post financial_setup_import_confirm_path, params: {
      step: "accounts",
      save_only: "1",
      sources: { "0" => { name: "Bancolombia Ahorros", bank: "Bancolombia", balance: "1000000" } }
    }

    assert_redirected_to financial_setup_step_path(step: :accounts)
    assert_equal current, @setup.reload.current_step
    source = @setup.reload.import_state("accounts")["sources"].first
    assert_equal "Bancolombia Ahorros", source["name"]
  end

  # ----------------------------------------------------------- remove source

  test "POST remove_source removes a manual row without touching import sources" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.replace_draft_sources("accounts", [
      { "identifier" => "8901", "name" => "cuenta davibank", "bank" => "Davibank", "kind" => "account", "balance" => "500000" }
    ])
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "187365986", "name" => "Cuenta de Ahorros", "bank" => "Banco de Bogotá", "kind" => "account", "balance" => "608" }
      ],
      "transactions" => [],
      "duplicates" => {}
    })
    @setup.save!

    post financial_setup_remove_source_path, params: { step: "accounts", idx: 0 }

    assert_redirected_to financial_setup_step_path(step: :accounts)
    assert_equal 0, @setup.reload.draft_sources("accounts").length
    import = @setup.import_state("accounts")
    assert_equal [ "Cuenta de Ahorros" ], import["sources"].map { |s| s["name"] }
  end

  test "POST remove_source removes an import row without touching manual sources" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.replace_draft_sources("accounts", [
      { "identifier" => "8901", "name" => "cuenta davibank", "bank" => "Davibank", "kind" => "account", "balance" => "500000" }
    ])
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "187365986", "name" => "Cuenta de Ahorros", "bank" => "Banco de Bogotá", "kind" => "account", "balance" => "608" }
      ],
      "transactions" => [],
      "duplicates" => {}
    })
    @setup.save!

    post financial_setup_remove_source_path, params: { step: "accounts", idx: 1 }

    assert_redirected_to financial_setup_step_path(step: :accounts)
    assert_equal [ "cuenta davibank" ], @setup.reload.draft_sources("accounts").map { |s| s["name"] }
    assert_equal 0, @setup.import_state("accounts")["sources"].length
  end

  test "POST save_edits keeps stored fields missing from the form via orig_key" do
    setup_record
    @setup.set_choice("loans", "manual")
    @setup.set_import_state("loans", {
      "sources" => [
        { "identifier" => "987654321", "name" => "Crédito Hipotecario", "bank" => "Banco", "kind" => "loan",
          "outstanding_balance" => "66959722", "monthly_payment" => "1130642" }
      ],
      "transactions" => [],
      "duplicates" => {}
    })
    @setup.save!

    # The combined editor freezes each row's key at render time. When a row is
    # submitted without an identifier (cleared by the user, or the input was
    # not rendered), the orig_key still matches the stored row so fields that
    # are not part of the form survive.
    post financial_setup_save_edits_path, params: {
      step: "loans",
      sources: {
        "0" => { origin: "import", orig_key: "987654321", name: "Crédito Hipotecario",
                 bank: "Banco", kind: "loan", outstanding_balance: "66959722", monthly_payment: "1130642" }
      }
    }

    assert_redirected_to financial_setup_step_path(step: :loans)
    source = @setup.reload.import_state("loans")["sources"].first
    assert_equal "987654321", source["identifier"]
    assert_equal "1130642", source["monthly_payment"]
  end

  # ----------------------------------------------------------- completion

  test "GET edit_all renders combined manual + import rows with origin tags" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.replace_draft_sources("accounts", [
      { "identifier" => "8901", "name" => "cuenta davibank", "bank" => "Davibank", "kind" => "account", "balance" => "500000" }
    ])
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1873", "name" => "Cuenta de Ahorros", "bank" => "Banco de Bogotá", "kind" => "account", "balance" => "608" }
      ],
      "transactions" => [],
      "duplicates" => {}
    })
    @setup.save!

    get financial_setup_edit_all_path(step: :accounts)
    assert_response :success
    assert_match(/cuenta davibank/, response.body)
    assert_match(/Cuenta de Ahorros/, response.body)
    assert_select "input[name='sources[0][origin]'][value='manual']"
    assert_select "input[name='sources[1][origin]'][value='import']"
  end

  test "POST save_edits routes each row back to its own store" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.replace_draft_sources("accounts", [
      { "identifier" => "8901", "name" => "cuenta davibank", "bank" => "Davibank", "kind" => "account", "balance" => "500000" }
    ])
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1873", "name" => "Cuenta de Ahorros", "bank" => "Banco de Bogotá", "kind" => "account", "balance" => "608" }
      ],
      "transactions" => [],
      "duplicates" => {}
    })
    @setup.save!

    post financial_setup_save_edits_path, params: {
      step: "accounts",
      sources: {
        "0" => { origin: "manual", name: "cuenta davibank edit", bank: "Davibank", kind: "account", balance: "500000", identifier: "8901" },
        "1" => { origin: "import", name: "Cuenta de Ahorros edit", bank: "Banco de Bogotá", kind: "account", balance: "608", identifier: "1873" }
      }
    }

    assert_redirected_to financial_setup_step_path(step: :accounts)
    manual = @setup.reload.draft_sources("accounts")
    assert_equal 1, manual.length
    assert_equal "cuenta davibank edit", manual.first["name"]
    imported = @setup.import_state("accounts")["sources"]
    assert_equal 1, imported.length
    assert_equal "Cuenta de Ahorros edit", imported.first["name"]
  end

  test "POST save_edits with only import rows leaves draft_sources empty" do
    setup_record
    @setup.set_choice("accounts", "import")
    @setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1873", "name" => "Cuenta de Ahorros", "bank" => "Banco de Bogotá", "kind" => "account", "balance" => "608" }
      ],
      "transactions" => [],
      "duplicates" => {}
    })
    @setup.save!

    post financial_setup_save_edits_path, params: {
      step: "accounts",
      sources: {
        "0" => { origin: "import", name: "Cuenta de Ahorros", bank: "Banco de Bogotá", kind: "account", balance: "608", identifier: "1873" }
      }
    }

    assert_redirected_to financial_setup_step_path(step: :accounts)
    assert_empty @setup.reload.draft_sources("accounts")
    assert_equal [ "Cuenta de Ahorros" ], @setup.import_state("accounts")["sources"].map { |s| s["name"] }
  end

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

  test "GET review shows imported credit cards and loans too" do
    setup_record
    @setup.set_choice("accounts", "skip")
    @setup.set_choice("credit_cards", "import")
    @setup.set_import_state("credit_cards", {
      "sources" => [
        { "identifier" => "5194", "name" => "Tarjeta de Crédito", "bank" => "Davibank", "kind" => "credit_card", "balance" => "1078648" }
      ],
      "duplicates" => {}
    })
    @setup.set_choice("loans", "import")
    @setup.set_import_state("loans", {
      "sources" => [
        { "identifier" => "3459", "name" => "Crédito de Vehículo", "bank" => "Santander", "kind" => "loan", "outstanding_balance" => "112068976" }
      ],
      "duplicates" => {}
    })
    @setup.save!

    get financial_setup_step_path(step: :review)
    assert_response :success
    assert_match(/Tarjeta de Crédito/, response.body)
    assert_match(/Crédito de Vehículo/, response.body)
    assert_match(/2 fuentes financieras configurada/, response.body)
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

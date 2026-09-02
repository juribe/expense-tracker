# frozen_string_literal: true

require "test_helper"

class CompleterTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "wizard_completer_test@example.com", password: "password123")
  end

  def setup_for(step = "accounts", choice: "manual")
    setup = @user.financial_setups.create!(status: "in_progress", current_step: 3)
    setup.set_choice(step, choice)
    setup.save!
    setup
  end

  def complete(setup)
    FinancialSetups::Completer.new(setup: setup).call
  end

  test "creates accounts entered manually" do
    setup = setup_for(choice: "manual")
    setup.replace_draft_sources("accounts", [
      { "name" => "Bancolombia Savings", "bank" => "Bancolombia", "balance" => "1000000" },
      { "name" => "Davivienda Checking", "bank" => "Davivienda", "balance" => "2500000" }
    ])
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 2, result.created_count
    assert_equal %w[account account], @user.money_sources.reload.pluck(:kind)
    assert_equal BigDecimal("1000000"), @user.money_sources.first.starting_balance
  end

  test "creates a credit card with its credit account" do
    setup = setup_for("credit_cards", choice: "manual")
    setup.replace_draft_sources("credit_cards", [
      {
        "name" => "Visa", "bank" => "Bancolombia", "kind" => "credit_card",
        "balance" => "500000", "credit_limit" => "10000000", "card_last_four" => "1234",
        "interest_rate" => "24.5", "interest_rate_type" => "effective_annual"
      }
    ])
    setup.save!

    result = complete(setup)
    assert result.ok?
    source = @user.money_sources.first
    assert_equal "credit_card", source.kind
    # Card debt is stored negative so usage keeps deducting available credit.
    assert_equal BigDecimal("-500000"), source.starting_balance
    assert_equal BigDecimal("500000"), source.used_credit
    assert_equal BigDecimal("9500000"), source.available_credit
    assert_equal BigDecimal("10000000"), source.credit_account.credit_limit
    assert_equal "1234", source.credit_account.card_last_four
    assert_equal BigDecimal("24.5"), source.credit_account.interest_rate
  end

  test "creates a loan with its credit account" do
    setup = setup_for("loans", choice: "manual")
    setup.replace_draft_sources("loans", [
      {
        "name" => "Car Loan", "bank" => "Banco", "kind" => "loan",
        "principal_amount" => "100000000",
        "outstanding_balance" => "95000000", "monthly_payment" => "2686800",
        "installment_count" => "48", "installments_paid" => "12",
        "interest_rate" => "21.27", "interest_rate_type" => "effective_annual"
      }
    ])
    setup.save!

    result = complete(setup)
    assert result.ok?
    source = @user.money_sources.first
    assert_equal "loan", source.kind
    assert_equal BigDecimal("100000000"), source.credit_account.principal_amount
    assert_equal BigDecimal("95000000"), source.credit_account.outstanding_balance
    assert_equal BigDecimal("2686800"), source.credit_account.installment_amount
    assert_equal 48, source.credit_account.installment_count
    assert_equal 12, source.credit_account.installments_paid
  end

  test "creates a recurring expense for a loan with a monthly payment" do
    setup = setup_for("loans", choice: "manual")
    setup.replace_draft_sources("loans", [
      {
        "name" => "Car Loan", "bank" => "Banco", "kind" => "loan",
        "outstanding_balance" => "95000000", "monthly_payment" => "2686800"
      }
    ])
    setup.save!

    assert_difference "RecurringTemplate.count", 1 do
      assert complete(setup).ok?
    end

    template = RecurringTemplate.last
    assert_equal "expense", template.kind
    assert_equal "monthly", template.frequency
    assert_equal BigDecimal("2686800"), template.amount
    assert_equal "wizard", template.source
    assert_equal @user.money_sources.first.id, template.money_source_id
  end

  test "creates a recurring expense for an imported credit card with a payment" do
    setup = setup_for("credit_cards", choice: "import")
    setup.set_import_state("credit_cards", {
      "sources" => [
        { "identifier" => "5194", "name" => "Tarjeta de Crédito", "bank" => "Davibank", "kind" => "credit_card",
          "balance" => "1078648", "credit_limit" => "20200000", "monthly_payment" => "1008855.0" }
      ],
      "duplicates" => { "5194" => { "choice" => "create" } }
    })
    setup.save!

    assert_difference "RecurringTemplate.count", 1 do
      assert complete(setup).ok?
    end
    assert_equal BigDecimal("1008855"), RecurringTemplate.last.amount
  end

  test "does not create a recurring expense without a monthly payment" do
    setup = setup_for("accounts", choice: "manual")
    setup.replace_draft_sources("accounts", [
      { "name" => "Savings", "bank" => "Bancolombia", "balance" => "100" }
    ])
    setup.save!

    assert_no_difference "RecurringTemplate.count" do
      assert complete(setup).ok?
    end
  end

  test "creates a manual loan with its contract number" do
    setup = setup_for("loans", choice: "manual")
    setup.replace_draft_sources("loans", [
      {
        "name" => "Crédito Hipotecario", "bank" => "Banco", "kind" => "loan",
        "identifier" => "73000123456",
        "outstanding_balance" => "66959722", "monthly_payment" => "1130642"
      }
    ])
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal "73000123456", @user.money_sources.first.identifier
  end

  test "skips blank manual rows" do
    setup = setup_for(choice: "manual")
    setup.replace_draft_sources("accounts", [
      { "name" => "", "bank" => "", "kind" => "account", "balance" => "" },
      { "name" => "Savings", "bank" => "Bancolombia", "balance" => "100" }
    ])
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 1, @user.money_sources.reload.count
    assert_equal "Savings", @user.money_sources.first.name
  end

  test "does nothing for skipped steps" do
    setup = setup_for(choice: "skip")
    assert complete(setup).ok?
    assert_equal 0, @user.money_sources.count
  end

  test "creates sources even when the choice is skip but data was added" do
    # Regression: the step screen's "Continuar" option kept a skip choice while
    # the user had already added sources — completion must still create them.
    setup = setup_for(choice: "skip")
    setup.replace_draft_sources("accounts", [
      { "name" => "Savings", "bank" => "Bancolombia", "balance" => "100" }
    ])
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "8901", "name" => "Davibank", "bank" => "Davibank", "kind" => "account", "balance" => "500" }
      ],
      "duplicates" => { "8901" => { "choice" => "create" } }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal %w[account account], @user.money_sources.reload.map(&:kind)
    assert_equal %w[Davibank Savings], @user.money_sources.map(&:name).sort
  end

  test "creates imported sources" do
    setup = setup_for(choice: "import")
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "duplicates" => { "1234" => { "choice" => "create" } }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    source = @user.money_sources.first
    assert_equal "Bancolombia Savings", source.name
    assert_equal "1234", source.identifier
    assert_equal BigDecimal("5420000"), source.starting_balance
  end

  test "updates an existing matched source on duplicate update" do
    existing = @user.money_sources.create!(name: "Bancolombia", kind: "account", bank: "Bancolombia", identifier: "1234")
    setup = setup_for(choice: "import")
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "duplicates" => { "1234" => { "choice" => "update" } }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 1, @user.money_sources.reload.count
    assert_equal "Bancolombia Savings", @user.money_sources.first.reload.name
    assert_equal existing.id, @user.money_sources.first.id
  end

  test "ignores a detected duplicate when told to" do
    @user.money_sources.create!(name: "Bancolombia", kind: "account", bank: "Bancolombia", identifier: "1234")
    setup = setup_for(choice: "import")
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "duplicates" => { "1234" => { "choice" => "ignore" } }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 1, @user.money_sources.reload.count
    assert_equal "Bancolombia", @user.money_sources.first.name
    assert_equal 0, result.created_count
  end

  test "honors duplicate choices stored as plain strings after review confirm" do
    existing = @user.money_sources.create!(name: "Bancolombia", kind: "account", bank: "Bancolombia", identifier: "1234")
    setup = setup_for(choice: "import")
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "duplicates" => { "1234" => "update" }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 1, @user.money_sources.reload.count
    assert_equal existing.id, @user.money_sources.first.id
    assert_equal "Bancolombia Savings", @user.money_sources.first.reload.name
  end

  test "honors ignore choices stored as plain strings after review confirm" do
    @user.money_sources.create!(name: "Bancolombia", kind: "account", bank: "Bancolombia", identifier: "1234")
    setup = setup_for(choice: "import")
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "duplicates" => { "1234" => "ignore" }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 1, @user.money_sources.reload.count
    assert_equal "Bancolombia", @user.money_sources.first.name
    assert_equal 0, result.created_count
  end

  test "completes without creating anything when an update target no longer exists" do
    setup = setup_for(choice: "import")
    setup.set_import_state("accounts", {
      "sources" => [
        { "identifier" => "1234", "name" => "Bancolombia Savings", "bank" => "Bancolombia",
          "kind" => "account", "balance" => "5420000" }
      ],
      "duplicates" => { "1234" => "update" }
    })
    setup.save!

    result = complete(setup)
    assert result.ok?
    assert_equal 0, @user.money_sources.reload.count
  end

  test "rolls back everything when any record is invalid" do
    setup = setup_for(choice: "manual")
    setup.replace_draft_sources("accounts", [
      { "name" => "Valid", "bank" => "Bancolombia", "balance" => "100" },
      { "name" => "", "bank" => "OnlyBank" }
    ])
    setup.save!

    result = complete(setup)
    assert_not result.ok?
    assert_equal 0, @user.money_sources.count
    assert result.errors.any?
  end
end

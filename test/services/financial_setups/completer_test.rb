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
    assert_equal BigDecimal("500000"), source.starting_balance
    assert_equal BigDecimal("10000000"), source.credit_account.credit_limit
    assert_equal "1234", source.credit_account.card_last_four
    assert_equal BigDecimal("24.5"), source.credit_account.interest_rate
  end

  test "creates a loan with its credit account" do
    setup = setup_for("loans", choice: "manual")
    setup.replace_draft_sources("loans", [
      {
        "name" => "Car Loan", "bank" => "Banco", "kind" => "loan",
        "outstanding_balance" => "95000000", "monthly_payment" => "2686800",
        "interest_rate" => "21.27", "interest_rate_type" => "effective_annual"
      }
    ])
    setup.save!

    result = complete(setup)
    assert result.ok?
    source = @user.money_sources.first
    assert_equal "loan", source.kind
    assert_equal BigDecimal("95000000"), source.credit_account.outstanding_balance
    assert_equal BigDecimal("2686800"), source.credit_account.installment_amount
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

# frozen_string_literal: true

require "test_helper"

module FinancialSetups
  class StepPresenterTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Test User", email: "step_presenter_test@example.com", password: "password123")
      @setup = @user.financial_setups.create!(status: "in_progress")
      @accounts_step = FinancialSetupWizard.step(:accounts)
    end

    def presenter(step = @accounts_step)
      StepPresenter.new(setup: @setup, step: step)
    end

    test "dedup_key prefers the digits-normalized identifier" do
      assert_equal "5986", StepPresenter.dedup_key({ "identifier" => "59 86", "bank" => "B", "name" => "N" })
      assert_equal "B-N", StepPresenter.dedup_key({ "identifier" => "", "bank" => "B", "name" => "N" })
      assert_equal "B-N", StepPresenter.dedup_key({ "bank" => "B", "name" => "N" })
    end

    test "combines and deduplicates manual and import rows" do
      @setup.replace_draft_sources("accounts", [
        { "identifier" => "5986", "name" => "Cuenta de Ahorros", "bank" => "Bancolombia", "balance" => "608" }
      ])
      @setup.set_import_state("accounts", {
        "sources" => [
          { "identifier" => "5986", "name" => "Cuenta de Ahorros", "bank" => "Bancolombia", "balance" => "608" },
          { "identifier" => "8901", "name" => "Ahorros Davibank", "bank" => "Davibank", "balance" => "500000" }
        ]
      })
      @setup.save!

      assert_equal 2, presenter.added_count
      assert presenter.has_added?
      assert_equal "Ahorros Davibank", presenter.added_sources.last["name"]
    end

    test "added_at resolves the combined list index" do
      @setup.replace_draft_sources("accounts", [
        { "identifier" => "5986", "name" => "Ahorros", "bank" => "Bancolombia" }
      ])
      @setup.set_import_state("accounts", {
        "sources" => [ { "identifier" => "8901", "name" => "Davibank", "bank" => "Davibank" } ]
      })
      @setup.save!

      assert_equal "Ahorros", presenter.added_at(0)["name"]
      assert_equal "Davibank", presenter.added_at(1)["name"]
      assert_nil presenter.added_at(2)
    end

    test "edit_rows tags origin and freezes the original key" do
      @setup.replace_draft_sources("accounts", [
        { "identifier" => "5986", "name" => "Ahorros", "bank" => "Bancolombia" }
      ])
      @setup.set_import_state("accounts", {
        "sources" => [ { "identifier" => "8901", "name" => "Davibank", "bank" => "Davibank" } ]
      })
      @setup.save!

      rows = presenter.edit_rows
      assert_equal "manual", rows.first["origin"]
      assert_equal "5986", rows.first["orig_key"]
      assert_equal "import", rows.last["origin"]
      assert_equal "8901", rows.last["orig_key"]
    end

    test "cash steps are not importable" do
      @setup.set_choice("cash", "manual")
      @setup.save!
      assert_not presenter(FinancialSetupWizard.step(:cash)).importable?
      assert presenter.importable?
    end

    test "masked_last_four prefers card_last_four and falls back to the identifier" do
      assert_equal "1234", presenter.masked_last_four({ "card_last_four" => "1234", "identifier" => "5678" })
      assert_equal "5678", presenter.masked_last_four({ "identifier" => "001123456 78" })
      assert_nil presenter.masked_last_four({ "identifier" => "" })
    end

    test "display_amount shows amount owed (current debt) for credit cards, not available credit" do
      step = FinancialSetupWizard.step(:credit_cards)
      row = { "balance" => "2000000", "credit_limit" => "10000000" }
      assert_equal "2000000", presenter(step).display_amount(row)
    end

    test "display_amount shows the debt even when a credit card has a limit" do
      step = FinancialSetupWizard.step(:credit_cards)
      row = { "balance" => "2000000", "credit_limit" => "10000000" }
      refute_equal "8000000", presenter(step).display_amount(row)
    end

    test "display_amount shows the debt for credit cards without a limit" do
      step = FinancialSetupWizard.step(:credit_cards)
      assert_equal "500", presenter(step).display_amount({ "balance" => "500", "credit_limit" => "0" })
      assert_equal "500", presenter(step).display_amount({ "balance" => "500" })
      assert_nil presenter(step).display_amount({ "balance" => "", "credit_limit" => "100" })
    end

    test "display_amount prefers outstanding balance for loans" do
      step = FinancialSetupWizard.step(:loans)
      row = { "balance" => "0.0", "outstanding_balance" => "67429112" }
      assert_equal "67429112", presenter(step).display_amount(row)
    end

    test "display_amount ignores stale balance extraction junk for loans" do
      step = FinancialSetupWizard.step(:loans)
      assert_nil presenter(step).display_amount({ "balance" => "100" })
    end

    test "display_amount shows the balance for accounts" do
      assert_equal "608", presenter.display_amount({ "balance" => "608" })
      assert_nil presenter.display_amount({ "balance" => "" })
    end

    test "display_label names the value per kind" do
      assert_equal "Deuda actual", presenter(FinancialSetupWizard.step(:credit_cards)).display_label({})
      assert_equal "Saldo pendiente", presenter(FinancialSetupWizard.step(:loans)).display_label({})
      assert_equal "Saldo actual", presenter(FinancialSetupWizard.step(:accounts)).display_label({})
      assert_equal "Saldo actual", presenter(FinancialSetupWizard.step(:cash)).display_label({})
    end
  end
end

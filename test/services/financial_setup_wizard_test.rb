# frozen_string_literal: true

require "test_helper"

class FinancialSetupWizardTest < ActiveSupport::TestCase
  test "defines accounts, credit cards, loans and review steps in order" do
    assert_equal %i[accounts credit_cards loans review], FinancialSetupWizard.step_keys
  end

  test "each source step declares a monetary kind" do
    kinds = FinancialSetupWizard.source_steps.map(&:kind)
    assert_equal %w[account credit_card loan], kinds
  end

  test "exposes the review step without a kind" do
    review = FinancialSetupWizard.step(:review)
    assert_nil review.kind
  end

  test "looks up a step by key" do
    step = FinancialSetupWizard.step("credit_cards")
    assert_equal :credit_cards, step.key
    assert_equal "credit_card", step.kind
    assert_equal "credit-card-2-front", step.icon
  end

  test "recognizes the manual, import and skip choices" do
    assert FinancialSetupWizard.choice?("manual")
    assert FinancialSetupWizard.choice?("import")
    assert FinancialSetupWizard.choice?("skip")
    assert_not FinancialSetupWizard.choice?("export")
  end

  test "valid_choice! rejects unknown choices" do
    assert_raises(ArgumentError) { FinancialSetupWizard.valid_choice!("export") }
  end

  test "builds a duplicate key from identifier or bank plus last four" do
    assert_equal "1234", FinancialSetupWizard.duplicate_key({ "identifier" => "1234" })
    assert_equal "Bancolombia-1234", FinancialSetupWizard.duplicate_key({ "bank" => "Bancolombia", "card_last_four" => "1234" })
    assert_equal "", FinancialSetupWizard.duplicate_key({})
    assert_equal "1234", FinancialSetupWizard.duplicate_key(ParsedStatement.new(identifier: "1234"))
  end
end

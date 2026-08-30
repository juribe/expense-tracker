# frozen_string_literal: true

require "test_helper"

class CreditAccountTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "credit_account_test@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Visa", kind: "credit_card")
  end

  test "belongs to a money source (one per source)" do
    account = @source.build_credit_account(credit_limit: 100)
    assert account.valid?
    assert_equal @source, account.money_source
  end

  test "credit_limit must be non-negative" do
    account = @source.build_credit_account(credit_limit: -1)
    assert_not account.valid?
    assert_includes account.errors[:credit_limit], I18n.t("errors.messages.greater_than_or_equal_to", count: 0)
  end

  test "interest_rate must be non-negative" do
    account = @source.build_credit_account(interest_rate: -5)
    assert_not account.valid?
    assert account.errors[:interest_rate].any?
  end

  test "interest_rate_type must be a valid value" do
    account = @source.build_credit_account(interest_rate_type: "bogus")
    assert_not account.valid?
    assert account.errors[:interest_rate_type].any?
  end

  test "card_last_four must be exactly four digits" do
    account = @source.build_credit_account(card_last_four: "12a4")
    assert_not account.valid?
    assert account.errors[:card_last_four].any?

    account = @source.build_credit_account(card_last_four: "1234")
    assert account.valid?
  end

  test "statement and payment due days must be between 1 and 31" do
    account = @source.build_credit_account(statement_day: 32, payment_due_day: 0)
    assert_not account.valid?
    assert account.errors[:statement_day].any?
    assert account.errors[:payment_due_day].any?
  end

  test "installment_count must be a positive integer" do
    account = @source.build_credit_account(installment_count: 0)
    assert_not account.valid?
    assert account.errors[:installment_count].any?
  end

  test "payment_frequency must be valid" do
    account = @source.build_credit_account(payment_frequency: "daily")
    assert_not account.valid?
    assert account.errors[:payment_frequency].any?
  end

  test "end_date must be after start_date" do
    account = @source.build_credit_account(start_date: Date.today, end_date: Date.yesterday)
    assert_not account.valid?
    assert account.errors[:end_date].any?
  end

  test "interest_rate_label appends EA suffix for effective annual" do
    account = @source.build_credit_account(interest_rate: 24.5, interest_rate_type: "effective_annual")
    assert_equal "24.50% EA", account.interest_rate_label
  end

  test "interest_rate_label appends NA suffix for nominal annual" do
    account = @source.build_credit_account(interest_rate: 21.27, interest_rate_type: "nominal_annual")
    assert_equal "21.27% NA", account.interest_rate_label
  end

  test "interest_rate_label appends M for monthly" do
    account = @source.build_credit_account(interest_rate: 2, interest_rate_type: "monthly")
    assert_equal "2.00% M", account.interest_rate_label
  end

  test "interest_rate_label returns nil when no rate" do
    account = @source.build_credit_account(interest_rate: nil)
    assert_nil account.interest_rate_label
  end
end

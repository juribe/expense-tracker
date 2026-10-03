# frozen_string_literal: true

require "test_helper"

module Statements
  class BalanceEffectTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Balance User", email: "statements_balance@example.com", password: "password123")
      @category = Category.create!(name: "Restaurantes", user: @user, category_type: "expense")
    end

    test "expenses linked to the credit card update the card cached balance" do
      card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: -100_000)
      before = card.reload.balance

      result = Statements::Confirmation.call(
        user: @user, money_source: card,
        movements: [ { "description" => "Restaurante XYZ", "amount" => "48500",
                       "date" => "2026-09-01", "category_id" => @category.id, "selected" => "1" } ]
      )

      assert result.success?
      assert_equal before - 48_500, card.reload.balance
      assert_equal 148_500, card.reload.used_credit
    end

    test "expenses linked to the loan update the cached balance" do
      loan = @user.money_sources.create!(name: "Libre inversión", kind: "loan", starting_balance: -1_000_000)
      loan.create_credit_account!(principal_amount: 1_000_000, outstanding_balance: 1_000_000)
      before = loan.reload.balance

      result = Statements::Confirmation.call(
        user: @user, money_source: loan,
        movements: [ { "description" => "Cuota", "amount" => "200000",
                       "date" => "2026-09-01", "category_id" => @category.id, "selected" => "1" } ]
      )

      assert result.success?
      assert_equal before - 200_000, loan.reload.balance
    end

    test "the payment expense lowers the funding account balance and clears card debt" do
      card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: -63_000)
      account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 500_000)
      before = account.reload.balance

      result = Statements::Confirmation.call(
        user: @user, money_source: card,
        movements: [],
        payment: { "register" => "1", "date" => "2026-09-05", "principal_amount" => "60000",
                   "interest_amount" => "3000", "insurance_amount" => "", "other_amount" => "",
                   "funding_money_source_id" => account.id }
      )

      assert result.success?
      assert_equal before - 63_000, account.reload.balance
      # Only the principal component reduces card debt; the 3000 interest
      # stays owed.
      assert_equal(-3_000, card.reload.balance)
      assert_equal BigDecimal("3000"), card.reload.used_credit
    end
  end
end

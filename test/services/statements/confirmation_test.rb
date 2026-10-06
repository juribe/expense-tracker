# frozen_string_literal: true

require "test_helper"

module Statements
  class ConfirmationTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Confirm User", email: "statements_confirm@example.com", password: "password123")
      @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
      @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 100_000)
      @category = Category.create!(name: "Restaurantes", user: @user, category_type: "expense")
      @payment_category = Category.create!(name: "Pagos de tarjeta", user: @user, category_type: "expense")
      @movements = [
        { "description" => "Restaurante XYZ", "amount" => "48500", "date" => "2026-09-01",
          "category_id" => @category.id, "selected" => "1", "money_source_id" => @card.id },
        { "description" => "Supermercado", "amount" => "210000", "date" => "2026-09-02",
          "category_id" => @category.id, "selected" => "0", "money_source_id" => @card.id },
        { "description" => "Farmacia", "amount" => "30000", "date" => "2026-09-03",
          "category_id" => @category.id, "selected" => "1", "money_source_id" => @card.id }
      ]
      @payment = {
        "register" => "1", "amount" => "63000", "date" => "2026-09-05",
        "description" => "Pago Tarjeta Visa", "category_id" => @payment_category.id,
        "principal_amount" => "60000",
        "interest_amount" => "3000", "insurance_amount" => "", "other_amount" => "",
        "funding_money_source_id" => @account.id
      }
    end

    test "creates expenses only for the selected movements" do
      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.success?
      descriptions = Expense.where(source: "statement_file")
                            .where.not(description: @payment["description"])
                            .order(:description).map(&:description)
      assert_equal [ "Farmacia", "Restaurante XYZ" ], descriptions
      created = result.result[:expenses]
      assert_equal 2, created.length
      assert created.all? { |expense| expense.money_source_id == @card.id }
    end

    test "creates the payment expense from the funding source and applies it to the debt" do
      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.success?
      payment = result.result[:payment]
      assert_equal @card.id, payment.money_source_id
      assert_equal BigDecimal("60000"), payment.principal_amount
      assert_equal BigDecimal("3000"), payment.interest_amount

      payment_expense = payment.expense
      assert_equal BigDecimal("63000"), payment_expense.amount.to_d.abs
      assert_equal @account.id, payment_expense.money_source_id
      assert_equal "Pago Tarjeta Visa", payment_expense.description
    end

    test "skips the payment when not requested" do
      @payment["register"] = "0"

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.success?
      assert_nil result.result[:payment]
      assert_equal 0, Payment.count
      assert_equal 2, Expense.where(source: "statement_file")
                             .where.not(description: @payment["description"]).count
    end

    test "the payment follows the typed distribution instead of the posted amount" do
      @payment["amount"] = "63000"
      @payment["principal_amount"] = "40000"
      @payment["interest_amount"] = "5000"

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.success?
      payment = result.result[:payment]
      assert_equal BigDecimal("45000"), payment.amount
      assert_equal BigDecimal("40000"), payment.principal_amount
      assert_equal BigDecimal("5000"), payment.interest_amount
      assert_equal BigDecimal("45000"), payment.expense.amount.to_d.abs
    end

    test "rolls everything back when the distribution is zeroed but an amount was posted" do
      @payment["interest_amount"] = ""
      @payment["principal_amount"] = ""
      @payment["insurance_amount"] = ""
      @payment["other_amount"] = ""

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.failure?
      assert_equal 0, Expense.where(source: "statement_file").count
      assert_equal 0, Payment.count
    end

    test "reports a validation failure without creating records" do
      @movements.first["amount"] = "0"

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.failure?
      assert_equal 0, Expense.count
      assert_equal 0, Payment.count
      assert result.errors.any?
    end

    test "an unknown funding source id does not break the payment" do
      @payment["funding_money_source_id"] = "999999"

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.success?
      assert_nil result.result[:payment].expense.money_source_id
    end

    test "skips selected movements that duplicate an existing expense" do
      Expense.create!(user: @user, category: @category, money_source: @card,
                      amount: -48_500, date: Date.new(2026, 9, 1), description: "Restaurante XYZ")

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: { "register" => "0" })

      assert result.success?
      assert_equal 1, result.result[:skipped_duplicates]
      amounts = result.result[:expenses].map { |expense| expense.amount.to_d.abs }
      assert_equal [ 30_000.to_d ], amounts
    end

    test "stale review does not create a movement twice" do
      # The expense was already created while the review page was open.
      Expense.create!(user: @user, category: @category, money_source: @card,
                      amount: -48_500, date: Date.new(2026, 9, 1), description: "Restaurante XYZ")
      Expense.create!(user: @user, category: @category, money_source: @card,
                      amount: -30_000, date: Date.new(2026, 9, 3), description: "Farmacia")

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: { "register" => "0" })

      assert result.success?
      assert_empty result.result[:expenses]
      assert_equal 2, result.result[:skipped_duplicates]
    end

    test "in-batch duplicates keep only one expense" do
      @movements[2][ "description" ] = "Farmacia"
      @movements << {
        "description" => "Farmacia", "amount" => "30000", "date" => "2026-09-03",
        "category_id" => @category.id, "selected" => "1", "money_source_id" => @card.id
      }

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: { "register" => "0" })

      assert result.success?
      assert_equal 2, result.result[:expenses].length
      assert_equal 1, result.result[:skipped_duplicates]
      assert_equal 2, Expense.where(source: "statement_file").count
    end

    test "unresolvable categories become review candidates, never new categories" do
      @movements = [ @movements[0] ]
      @movements[0] = { "description" => "MAXIDIFICACION RARA", "amount" => "48500",
                        "date" => "2026-09-01", "category_id" => "",
                        "category_name" => "MAXIDIFICACION", "selected" => "1",
                        "money_source_id" => @card.id }
      categories_before = Category.count

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: { "register" => "0" })

      assert result.success?
      assert_equal 1, result.result[:candidates].length
      assert_equal categories_before, Category.count
      assert_equal 0, Expense.where(source: "statement_file").count

      parked = result.result[:candidates].first
      assert_equal "needs_review", parked.status
      assert_equal "statement_file", parked.source
      assert_includes parked.missing_fields, "category_id"
      assert_equal 48_500.to_d, parked.amount
    end

    test "resolvable category names create the expense with the matched category" do
      @movements[0] = { "description" => "Restaurante XYZ", "amount" => "48500",
                        "date" => "2026-09-01", "category_id" => "",
                        "category_name" => "Restaurantes", "selected" => "1",
                        "money_source_id" => @card.id }

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: { "register" => "0" })

      assert result.success?
      assert_empty result.result[:candidates]
      expense = result.result[:expenses].first
      assert_equal @category.id, expense.category_id
    end

    test "mixed batch parks only the uncertain rows" do
      @movements[1]["selected"] = "1"
      @movements[1]["category_id"] = ""
      @movements[1]["category_name"] = "COSA EXTRANISIMA SIN SENTIDO"

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: { "register" => "0" })

      assert result.success?
      assert_equal 2, result.result[:expenses].length
      assert_equal 1, result.result[:candidates].length
    end

    test "payment without a usable category is rejected" do
      @payment["category_id"] = ""

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.failure?
      assert_equal 0, Expense.where(source: "statement_file").count
      assert_equal 0, Payment.count
    end

    test "payment with a foreign category id is rejected" do
      other_user = User.create!(name: "Other", email: "statements_confirm_other@example.com", password: "password123")
      foreign = Category.create!(name: "Ajenos", user: other_user, category_type: "expense")
      @payment["category_id"] = foreign.id

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.failure?
      assert_equal 0, Payment.count
    end

    test "parked candidates are rolled back when the payment fails" do
      @movements[0] = { "description" => "MAXIDIFICACION RARA", "amount" => "48500",
                        "date" => "2026-09-01", "category_id" => "",
                        "category_name" => "MAXIDIFICACION", "selected" => "1",
                        "money_source_id" => @card.id }
      @payment["category_id"] = ""

      result = Statements::Confirmation.call(user: @user, money_source: @card,
                                             movements: @movements, payment: @payment)

      assert result.failure?
      assert_equal 0, ExpenseCandidate.where(source: "statement_file").count
      assert_equal 0, Expense.where(source: "statement_file").count
    end
  end
end

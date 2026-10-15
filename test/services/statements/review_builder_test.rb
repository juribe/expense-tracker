# frozen_string_literal: true

require "test_helper"

module Statements
  class ReviewBuilderTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Review User", email: "statements_review@example.com", password: "password123")
      @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
      @document = Statements::Document.new(
        engine: :ai,
        summary: Statements::Summary.new(total_due: "1250300", min_payment: "62515",
                                         interest_charged: "45200", due_date: "2026-09-04",
                                         statement_date: "2026-08-25"),
        source: ParsedStatement.new(kind: "credit_card", name: "Visa", bank: "Davivienda",
                                    card_last_four: "8976"),
        movements: [
          { date: "2026-08-23", description: "Restaurante XYZ", amount: 48_500, type: "expense" },
          { date: "2026-08-24", description: "Supermercado", amount: 210_000, type: "expense" },
          { date: "2026-08-25", description: "Pago recibido", amount: 500_000, type: "income" }
        ]
      )
    end

    test "assigns the target money source to every candidate" do
      review = Statements::ReviewBuilder.call(user: @user, document: @document, money_source: @card)

      assert_equal [ @card.id, @card.id ], review.candidates.map(&:money_source_id)
      assert_equal [ "statement", "statement" ], review.candidates.map(&:money_source_source)
      assert_equal "statement_file", review.candidates.first.source
    end

    test "keeps income movements out of the candidates and lists them as credits" do
      review = Statements::ReviewBuilder.call(user: @user, document: @document, money_source: @card)

      assert_equal [ "Restaurante XYZ", "Supermercado" ], review.candidates.map(&:description)
      assert_equal [ "Pago recibido" ], review.credits.map { |movement| movement[:description] }
    end

    test "flags movements that already exist as expenses" do
      Expense.create!(user: @user, amount: 48_500, description: "Restaurante XYZ",
                      date: Date.new(2026, 8, 23), kind: "expense", source: "manual",
                      money_source: @card)

      review = Statements::ReviewBuilder.call(user: @user, document: @document, money_source: @card)

      assert review.candidates.first.duplicate
      assert_equal :existing, review.candidates.first.duplicate_kind
      assert_not review.candidates.second.duplicate
      assert_nil review.candidates.second.duplicate_kind
    end

    test "marks a repeated charge inside the statement as in-statement on every row" do
      document = Statements::Document.new(
        engine: :ai,
        summary: @document.summary,
        source: @document.source,
        movements: [
          { date: "2026-08-23", description: "Doble cobro", amount: 12_000, type: "expense" },
          { date: "2026-08-23", description: "Doble cobro", amount: 12_000, type: "expense" }
        ]
      )

      review = Statements::ReviewBuilder.call(user: @user, document: document, money_source: @card)

      kinds = review.candidates.map(&:duplicate_kind)
      assert_equal [ :in_statement, :in_statement ], kinds
      assert_not review.candidates.first.duplicate
      assert review.candidates.second.duplicate
    end

    test "resolves categories from stored classification reuse" do
      category = Category.create!(name: "Restaurantes", user: @user, category_type: "expense")
      ActivityClassification.record!(user: @user, name: "Restaurante XYZ",
                                     category: category, source: "user")

      review = Statements::ReviewBuilder.call(user: @user, document: @document, money_source: @card)

      assert_equal category.id, review.candidates.first.category_id
    end

    test "suggests a payment from the summary when no payment movement exists" do
      document = Statements::Document.new(
        engine: :ai,
        summary: @document.summary,
        source: @document.source,
        movements: [ { date: "2026-08-23", description: "Restaurante XYZ", amount: 48_500, type: "expense" } ]
      )

      review = Statements::ReviewBuilder.call(user: @user, document: document, money_source: @card)

      suggestion = review.payment_suggestion
      assert_equal BigDecimal("1250300"), suggestion[:amount]
      assert_equal Date.new(2026, 9, 4), suggestion[:date]
      assert_equal BigDecimal("1205100"), suggestion[:principal_amount]
      assert_equal BigDecimal("45200"), suggestion[:interest_amount]
      assert_match(/Visa/, suggestion[:description])
    end

    test "suggests the payment from the statement's payment movement when present" do
      document = Statements::Document.new(
        engine: :ai,
        summary: @document.summary,
        source: @document.source,
        movements: [ { date: "2026-08-25", description: "Pago recibido", amount: 900_000, type: "income" } ]
      )

      review = Statements::ReviewBuilder.call(user: @user, document: document, money_source: @card)

      suggestion = review.payment_suggestion
      assert_equal BigDecimal("900000"), suggestion[:amount]
      assert_equal Date.new(2026, 8, 25), suggestion[:date]
      assert_match(/Visa/, suggestion[:description])
    end

    test "does not suggest a payment that was already registered" do
      document = Statements::Document.new(
        engine: :ai,
        summary: @document.summary,
        source: @document.source,
        movements: [ { date: "2026-08-25", description: "Pago recibido", amount: 500_000, type: "income" } ]
      )
      register_payment(amount: 500_000, date: Date.new(2026, 8, 25))

      review = Statements::ReviewBuilder.call(user: @user, document: document, money_source: @card)

      assert_nil review.payment_suggestion
    end

    test "still suggests the payment when the registered one differs" do
      document = Statements::Document.new(
        engine: :ai,
        summary: @document.summary,
        source: @document.source,
        movements: [ { date: "2026-08-25", description: "Pago recibido", amount: 500_000, type: "income" } ]
      )
      register_payment(amount: 500_000, date: Date.new(2026, 8, 20))

      review = Statements::ReviewBuilder.call(user: @user, document: document, money_source: @card)

      assert_equal BigDecimal("500000"), review.payment_suggestion[:amount]
    end

    test "works without a summary and without income movements" do
      document = Statements::Document.new(
        engine: :ai,
        summary: nil,
        source: nil,
        movements: [ { date: "2026-08-23", description: "Restaurante XYZ", amount: 48_500, type: "expense" } ]
      )

      review = Statements::ReviewBuilder.call(user: @user, document: document, money_source: @card)

      assert_nil review.payment_suggestion
      assert_equal 1, review.candidates.length
      assert_nil review.source
    end

    test "prefers the statement source when no explicit target is given" do
      source = @user.money_sources.create!(name: "Visa Davivienda", kind: "credit_card", starting_balance: 0)
      source.create_credit_account!(card_last_four: "8976")

      review = Statements::ReviewBuilder.call(user: @user, document: @document)

      assert_equal "Visa Davivienda", review.candidates.first.money_source_name
    end

    private

    def register_payment(amount:, date:)
      funding = @user.money_sources.create!(name: "Ahorros #{amount}", kind: "account", starting_balance: 0)
      expense = Expense.create!(user: @user, amount: amount, description: "Pago Visa",
                                date: date, kind: "expense", source: "statement_file",
                                money_source: funding)
      Payment.create!(user: @user, expense: expense, money_source: @card, amount: amount,
                      principal_amount: amount)
    end
  end
end

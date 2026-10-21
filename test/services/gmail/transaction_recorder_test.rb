# frozen_string_literal: true

require "test_helper"

module Gmail
  class TransactionRecorderTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Recorder User",
                           email: "gmail_recorder_#{SecureRandom.hex(6)}@example.com",
                           password: "password123")
      @mercado = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")
      @money_source = @user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")
      @transaction = {
        type: "expense",
        amount: BigDecimal("48500"),
        currency: "COP",
        merchant: "SAO",
        category: "groceries",
        occurred_at: "2026-08-23T14:30:00",
        confidence: 0.9,
        card_last_four: "1234",
        bank: "Bancolombia"
      }
    end

    def recorder(subject: "Compra aprobada")
      Gmail::TransactionRecorder.new(user: @user, gmail_message_id: "msg-1", subject: subject)
    end

    test "creates an expense with the resolved category and does not create categories" do
      result = nil

      assert_no_difference -> { Category.count } do
        assert_difference -> { Expense.count }, 1 do
          result = recorder.call(@transaction, money_source: @money_source)
        end
      end

      assert result.expense?
      assert_nil result.candidate
      expense = result.expense
      assert_equal @mercado, expense.category
      assert_equal "gmail", expense.source
      assert_equal "msg-1", expense.gmail_message_id
      assert_equal "SAO", expense.description
      assert_equal @money_source, expense.money_source
    end

    test "creates a needs_review candidate when the category does not resolve" do
      @mercado.destroy!
      result = nil

      assert_no_difference -> { Expense.count } do
        assert_no_difference -> { Category.count } do
          assert_difference -> { ExpenseCandidate.count }, 1 do
            result = recorder.call(@transaction, money_source: @money_source)
          end
        end
      end

      assert result.candidate?
      assert_nil result.expense
      candidate = result.candidate
      assert_equal @user, candidate.user
      assert_equal "gmail", candidate.source
      assert_nil candidate.category_id
      assert_nil candidate.category_suggestion
      assert_equal "msg-1", candidate.metadata["gmail_message_id"]
      assert_equal "groceries", candidate.metadata["category_hint"]
      assert_equal "Compra aprobada", candidate.original_input
      assert_equal "SAO", candidate.description
      assert_equal BigDecimal("48500"), candidate.amount
      assert_equal Date.new(2026, 8, 23), candidate.date
      assert_equal @money_source, candidate.money_source
      assert_equal "needs_review", candidate.status
    end

    test "uses the merchant as the activity for learned classifications" do
      transporte = Category.create!(name: "Transporte", user: @user, is_default: false, category_type: "expense")
      ActivityClassification.record!(user: @user, name: "EDS", category: transporte, source: "user")
      transaction = @transaction.merge(category: nil, merchant: "EDS")

      result = recorder.call(transaction, money_source: @money_source)

      assert result.expense?
      assert_equal transporte, result.expense.category
      assert_equal 0, ExpenseCandidate.where(user: @user).count
    end

    test "creates a candidate when no money source can be detected, even with a resolved category" do
      result = nil

      assert_no_difference -> { Expense.count } do
        assert_difference -> { ExpenseCandidate.count }, 1 do
          result = recorder.call(@transaction)
        end
      end

      assert result.candidate?
      assert_nil result.expense
      assert_nil result.candidate.money_source
      assert_equal "needs_review", result.candidate.status
      assert_equal [ "money_source_id" ], result.candidate.missing_fields
    end

    test "accepts string-keyed transactions from the review payload" do
      result = recorder.call(@transaction.deep_stringify_keys, money_source: @money_source)

      assert result.expense?
      assert_equal @mercado, result.expense.category
    end
  end
end

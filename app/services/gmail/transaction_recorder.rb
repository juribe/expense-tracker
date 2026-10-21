# frozen_string_literal: true

module Gmail
  # Persists one extracted Gmail transaction as an Expense only when both its
  # category resolves to an existing user category AND the money source is
  # known; anything without either lands as a reviewable ExpenseCandidate.
  # Never creates categories.
  #
  #   Gmail::TransactionRecorder.new(user: user, gmail_message_id: id, subject: subject)
  #     .call(transaction, money_source: source)
  class TransactionRecorder
    Result = Struct.new(:expense, :candidate, keyword_init: true) do
      def expense?
        expense.present?
      end

      def candidate?
        candidate.present?
      end
    end

    def initialize(user:, gmail_message_id:, subject: nil)
      @user = user
      @gmail_message_id = gmail_message_id.to_s
      @subject = subject.to_s
    end

    def call(transaction, money_source: nil)
      transaction = transaction.to_h.symbolize_keys
      category = resolve_category(transaction)
      # A real expense without a funding source would breach the money-source
      # rule; the candidate pipeline collects these for review instead.
      if money_source.blank? || category.nil?
        return create_candidate(transaction, money_source, category)
      end

      create_expense(transaction, category, money_source)
    end

    private

    def resolve_category(transaction)
      Categories::ClosestResolver.call(
        user: @user,
        name: transaction[:category],
        activity: transaction[:merchant]
      ).category
    end

    def create_expense(transaction, category, money_source)
      expense = Expenses::Create.call(
        user: @user,
        amount: transaction[:amount],
        description: transaction[:merchant],
        category: category,
        occurred_at: occurred_at_for(transaction),
        source: :gmail,
        gmail_message_id: @gmail_message_id,
        money_source: money_source
      )
      Result.new(expense: expense)
    end

    def create_candidate(transaction, money_source, category = nil)
      candidate = ExpenseCandidate.create!(
        user: @user,
        amount: transaction[:amount],
        date: occurred_at_for(transaction).to_date,
        description: transaction[:merchant],
        category: category,
        money_source: money_source,
        source: "gmail",
        confidence: transaction[:confidence],
        original_input: @subject.presence,
        metadata: candidate_metadata(transaction)
      )
      Result.new(candidate: candidate)
    end

    def candidate_metadata(transaction)
      {
        "gmail_message_id" => @gmail_message_id,
        "category_hint" => transaction[:category],
        "currency" => transaction[:currency],
        "bank" => transaction[:bank],
        "card_last_four" => transaction[:card_last_four]
      }.compact
    end

    def occurred_at_for(transaction)
      Time.zone.parse(transaction[:occurred_at].to_s) || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end
  end
end

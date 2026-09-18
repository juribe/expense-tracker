# frozen_string_literal: true

module ExpenseResolver
  class CandidateDetector
    attr_accessor :expense, :user, :categories, :money_source_detector

    def self.call(expense:, user:, categories: nil, money_source_detector: nil)
      new(expense: expense, user: user, categories: categories, money_source_detector: money_source_detector).call
    end

    def initialize(expense:, user:, categories: nil, money_source_detector: nil)
      self.expense = expense
      self.user = user
      self.categories = categories
      self.money_source_detector = money_source_detector
    end

    def call
      ExpenseCandidate.new(
        amount: amount_result.amount,
        currency: ExpenseCandidate::DEFAULT_CURRENCY,
        category_id: category_result.category&.id,
        category_name: category_result.category_name,
        description: description_result.description,
        date: date_result.date,
        source: "playground",
        classification_source: "ai",
        suggested_category_name: category_result.suggested_category_name,
        confidence: expense.confidence,
        money_source_name: money_source_result.money_source_name,
        money_source_id: money_source_result.money_source&.id
      )
    end

    def amount_result
      @amount_result ||= AmountResult.call(
        amount: expense.amount,
        text: expense.original_text
      )
    end

    def category_result
      @category_result ||= CategoryResult.call(
        expense: expense,
        user: user,
        categories: categories
      )
    end

    def description_result
      @description_result ||= DescriptionResult.call(expense: expense)
    end

    def date_result
      @date_result ||= DateResult.call(expense: expense)
    end

    def money_source_result
      @money_source_result ||= MoneySourceResult.call(
        expense: expense,
        user: user,
        money_source_detector: money_source_detector
      )
    end
  end
end

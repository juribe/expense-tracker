# frozen_string_literal: true

module ExpenseResolver
  class MoneySourceResult
    Result = Struct.new(:money_source, :money_source_name) do
    end

    attr_accessor :expense, :user, :money_source_detector, :rules

    def self.call(expense:, user:, money_source_detector: nil, rules: nil)
      new(expense: expense, user: user, money_source_detector: money_source_detector, rules: rules).call
    end

    def initialize(expense:, user:, money_source_detector: nil, rules: nil)
      self.expense = expense
      self.user = user
      self.money_source_detector = money_source_detector
      self.rules = rules
    end

    def call
      money_source = money_source_detector.call(expense.original_text)
      return Result.new(nil, expense.money_source_hint) if money_source.nil?

      Result.new(money_source, money_source.name)
    end
  end
end

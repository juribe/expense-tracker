# frozen_string_literal: true

module ExpenseResolver
  class DescriptionResult
    Result = Struct.new(:description) do
    end

    attr_accessor :expense

    def self.call(expense:)
      new(expense: expense).call
    end

    def initialize(expense:)
      self.expense = expense
    end

    def call
      Result.new(description)
    end

    private
    def description
      stripped_string(expense.description) || stripped_string(expense.original_text)
    end

    def stripped_string(value)
      value.to_s.strip.presence
    end
  end
end

# frozen_string_literal: true

module ExpenseResolver
  class MoneySourceResult
    Result = Struct.new(:money_source, :money_source_name) do
    end

    attr_accessor :expense, :user, :money_source_detector, :rules, :text

    def self.call(expense:, user:, money_source_detector: nil, rules: nil, text: nil)
      new(expense: expense, user: user, money_source_detector: money_source_detector, rules: rules, text: text).call
    end

    def initialize(expense:, user:, money_source_detector: nil, rules: nil, text: nil)
      self.expense = expense
      self.user = user
      self.money_source_detector = money_source_detector
      self.rules = rules
      self.text = text
    end

    def call
      money_source = money_source_detector.call(source_text)
      return Result.new(nil, expense.money_source_hint) if money_source.nil?

      Result.new(money_source, money_source.name)
    end

    private

    # A single mention of a source in the message usually applies to every
    # detected expense (e.g. "gasté 50 mil en restaurante y 20 mil en
    # parqueadero desde nequi"), so the full text is preferred when available.
    def source_text
      text.presence || expense.original_text
    end
  end
end

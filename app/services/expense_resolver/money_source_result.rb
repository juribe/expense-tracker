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
      # Channel processors may have already detected the source (e.g. the
      # image pipeline from the user's note or the receipt's OCR text); in
      # that case the pre-set id wins and no detection runs.
      return preset_result if preset_money_source?

      money_source = money_source_detector.call(source_text)
      return Result.new(nil, expense.money_source_hint) if money_source.nil?

      Result.new(money_source, money_source.name)
    end

    private

    def preset_money_source?
      expense.respond_to?(:money_source_id) && expense.money_source_id.present?
    end

    def preset_result
      source = user&.money_sources&.find_by(id: expense.money_source_id)
      Result.new(source, source&.name || expense.money_source_name)
    end

    # A single mention of a source in the message usually applies to every
    # detected expense (e.g. "gasté 50 mil en restaurante y 20 mil en
    # parqueadero desde nequi"), so the full text is preferred when available.
    def source_text
      text.presence || expense.original_text
    end
  end
end

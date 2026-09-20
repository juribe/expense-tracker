# frozen_string_literal: true

module ExpenseResolver
  class NaturalLanguageParser
    attr_accessor :text, :current_date, :user, :categories, :context, :recording

    def self.call(text:, current_date: Date.current, user: nil, categories: nil, context: nil, recording: nil)
      new(text: text, current_date: current_date, user: user, categories: categories, context: context, recording: recording).call
    end

    def initialize(text:, current_date:, user: nil, categories: nil, context: nil, recording: nil)
      @text = text.to_s.strip
      @current_date = current_date.to_date
      @user = user
      @categories = categories
      @context = context
      @recording = recording
    end

    def call
      return ServiceResult.error([ "Text is empty." ]) if text.blank?

      router_result = Ai::Router.call(
        task: :conversation_expense_parsing,
        input: text,
        context: { user: user, today: current_date, categories: categories, context: context, execution: recording&.execution }
      )
      return ServiceResult.error([ router_result.error.presence || "AI parsing failed." ]) unless router_result.ok?

      recording&.add_step(:extraction, router_result.data)
      ServiceResult.success(router_result.data)
    end
  end
end

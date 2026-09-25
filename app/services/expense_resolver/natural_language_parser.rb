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
        context: { user: user, today: current_date, categories: categories_names, context: context, execution: recording&.execution }
      )
      return ServiceResult.error([ router_result.error.presence || "AI parsing failed." ]) unless router_result.ok?

      entries = router_result.data
      recording&.add_step(:extraction, entries)
      resolve_missing_categories(entries)
      ServiceResult.success(entries)
    end

    private

    # Second, optional AI call: only expenses whose category came back null
    # are sent, and a failure never breaks the parse.
    def resolve_missing_categories(entries)
      pending = entries.each_with_index.select { |entry, _| entry.category.nil? && entry.description.present? }
      return if pending.empty?

      items = pending.map.with_index do |(entry, _), position|
        { "index" => position, "description" => entry.description }
      end

      suggestion_result = Ai::Router.call(
        task: :category_suggestion,
        input: items,
        context: { user: user, execution: recording&.execution }
      )

      if suggestion_result.ok?
        recording&.add_step(:category_suggestion, suggestion_result.data)
        apply_suggestions(entries, pending, suggestion_result.data)
      else
        Rails.logger.error("Category suggestion failed: #{suggestion_result.error}")
      end
    end

    def apply_suggestions(entries, pending, suggestions)
      pending.each_with_index do |(entry, _), position|
        suggestion = suggestions[position.to_s] || suggestions[position]
        next if suggestion.blank?

        entry.category_suggestion = suggestion
      end
    end

    # Explicitly passed categories win; otherwise the user's expense
    # categories are used so the model can only pick from real ones.
    def categories_names
      @categories_names ||= Array(categories).presence ||
                            (user ? Category.for_user(user).expenses.order(:name).map(&:name) : [])
    end
  end
end

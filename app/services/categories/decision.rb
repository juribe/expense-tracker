# frozen_string_literal: true

module Categories
  # The single place where the category decision is made for every channel
  # (text, voice, image): it runs Categories::HeuristicResolver ONCE and then
  # applies the one naming/warning policy for whatever did not match. To
  # change how categories are decided or presented, change only this class.
  #
  #   Categories::Decision.call(user:, name:, activity:, category_id: nil, suggestion: nil)
  #     => Result(category, category_name, suggested_category_name, warnings)
  class Decision
    Result = Struct.new(:category, :category_name, :suggested_category_name, :warnings, keyword_init: true) do
      def suggestion?
        suggested_category_name.present?
      end
    end

    def self.call(user:, name:, activity: nil, category_id: nil, suggestion: nil)
      new(user: user, name: name, activity: activity, category_id: category_id, suggestion: suggestion).call
    end

    def initialize(user:, name:, activity: nil, category_id: nil, suggestion: nil)
      @user = user
      @name = name.presence
      @activity = activity
      @category_id = category_id
      @suggestion = suggestion.presence
    end

    def call
      warnings = []
      resolved = resolver.resolve_category(@name, @category_id, activity: @activity)

      if resolved
        Result.new(category: resolved, category_name: resolved.name,
                   suggested_category_name: nil, warnings: warnings)
      elsif @name.present? && !resolver.rejected_category_name
        # An unmatched but plausible name: keep it so the user can create or
        # pick it when confirming.
        warnings << "We could not match the category \"#{@name}\". You can create it or pick an existing one when you confirm."
        Result.new(category: nil, category_name: @name,
                   suggested_category_name: @name, warnings: warnings)
      elsif (suggested = fallback_suggestion).present?
        warnings << "No matching category found. Suggesting the new category \"#{suggested}\"; confirm to create it or pick an existing one."
        Result.new(category: nil, category_name: suggested,
                   suggested_category_name: suggested, warnings: warnings)
      else
        warnings << "We could not determine a category for this expense. You can assign it when you confirm."
        Result.new(category: nil, category_name: nil,
                   suggested_category_name: nil, warnings: warnings)
      end
    end

    private

    def resolver
      @resolver ||= Categories::HeuristicResolver.new(user: @user, name: @name, activity: @activity)
    end

    # An externally supplied suggestion (e.g. the AI category-suggestion task)
    # wins over the heuristic name derived from the activity text.
    def fallback_suggestion
      @suggestion || resolver.suggest_category_name(@activity)
    end
  end
end

# frozen_string_literal: true

module ExpenseResolver
  class CategoryResult
    Result = Struct.new(:category, :category_name, :suggested_category_name, :warnings, keyword_init: true) do
      def suggestion?
        suggested_category_name.present?
      end
    end

    attr_accessor :expense, :user, :categories, :rules

    def self.call(expense:, user:, categories:, rules: nil)
      new(expense: expense, user: user, categories: categories, rules: rules).call
    end

    def initialize(expense:, user:, categories:, rules: nil)
      self.expense = expense
      self.user = user
      self.categories = categories
      self.rules = rules
    end

    def call
      # The decision is centralized in Categories::Decision (resolution +
      # naming + warnings), so every channel produces the same outcome.
      decision = ::Categories::Decision.call(
        user: user,
        name: raw_category,
        activity: activity,
        category_id: safe_category_id
      )

      Result.new(
        category: decision.category,
        category_name: decision.category_name,
        suggested_category_name: decision.suggested_category_name,
        warnings: decision.warnings
      )
    end

    private

    def activity
      expense.respond_to?(:description) ? expense.description.presence : nil
    end

    def safe_category_id
      expense.respond_to?(:category_id) ? expense.category_id : nil
    end

    def raw_category
      expense.category.to_s.strip.presence
    end
  end
end

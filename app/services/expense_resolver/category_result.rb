# frozen_string_literal: true

module ExpenseResolver
  class CategoryResult
    Result = Struct.new(:category, :category_name, :suggested_category_name) do
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
      resolved = category_resolver.resolve_category(raw_category, safe_category_id, activity: activity)
      return Result.new(nil, nil, raw_category) if resolved.nil?

      Result.new(resolved, resolved.name, nil)
    end

    private

    # Category resolution is centralized in Categories::HeuristicResolver:
    # exact normalized name, learned activity mappings, English->Spanish
    # aliases, the parking/housing guards and a similarity fold.
    def category_resolver
      @category_resolver ||= ::Categories::HeuristicResolver.new(
        user: user,
        name: raw_category,
        activity: activity
      )
    end

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

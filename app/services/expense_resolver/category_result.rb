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
      resolved = category_in_database
      return Result.new(nil, nil, raw_category) if resolved.nil?

      Result.new(resolved, resolved.name, nil)
    end

    private

    def raw_category
      expense.category.to_s.strip.presence
    end

    def category_in_database(name = raw_category)
      categories.find { |record| record.name == name }
    end

    def category_names
      categories.map(&:name)
    end
  end
end

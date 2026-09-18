# frozen_string_literal: true

# Resolves an AI-suggested category label to a Category the user can own.
# Tries, in order, an explicitly passed allowed set, the user's expense
# categories, then the application defaults (mirrors
# NaturalLanguageExpenseParser). When the label matches a real Category it's
# used as-is; any other case is reported as a "new" category the caller may
# offer as a suggestion.
#
#   result = CategoryResolver.call(category_name: "Transporte", user: user)
#   result.category               # => Category record or nil
#   result.category_name          # => "Transporte" (user's record name)
#   result.suggested_category_name # => nil when resolved, else the raw label
#
# Never persists anything.
class CategoryResolver
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
    Result.new(
      resolved,
      resolved&.name || raw_category,
      resolved ? nil : raw_category
    )
  end

  private

  def raw_category
    expense["category"].to_s.strip.presence
  end

  def category_in_database(name = raw_category)
    categories.find { |record| record.name == name }
  end

  def category_names
    categories.map(&:name)
  end
end

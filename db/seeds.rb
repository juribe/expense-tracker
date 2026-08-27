# frozen_string_literal: true

# Default categories — shared across all users
EXPENSE_DEFAULTS = [
  "Food & Dining",
  "Transportation",
  "Housing",
  "Utilities",
  "Health",
  "Entertainment",
  "Shopping",
  "Education",
  "Travel",
  "Other"
].freeze

INCOME_DEFAULTS = [
  "Salary",
  "Freelance",
  "Investments",
  "Business",
  "Gifts",
  "Other"
].freeze

EXPENSE_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "expense")
end

INCOME_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "income")
end

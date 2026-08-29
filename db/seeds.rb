# frozen_string_literal: true

# Default categories — shared across all users
EXPENSE_DEFAULTS = I18n.t("categories.defaults.expense").freeze
INCOME_DEFAULTS = I18n.t("categories.defaults.income").freeze

EXPENSE_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "expense")
end

INCOME_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "income")
end

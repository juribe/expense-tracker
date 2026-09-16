# frozen_string_literal: true

# Default categories — shared across all users
EXPENSE_DEFAULTS = I18n.t("categories.defaults.expense").freeze
INCOME_DEFAULTS = I18n.t("categories.defaults.income").freeze

EXPENSE_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "expense")
end

# "Comida" is the umbrella; "Restaurante" lives under it as a shared subcategory
# so restaurant/delivery expenses roll up into ["Comida", "Restaurante"].
comida = Category.find_by(name: "Comida", is_default: true, category_type: "expense")
if comida
  restaurante = Category.find_or_initialize_by(name: "Restaurante", is_default: true, category_type: "expense")
  restaurante.parent = comida
  restaurante.slug ||= "restaurante"
  restaurante.save!
end

INCOME_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "income")
end

# Financial email catalog: Colombian institutions, global financial keywords
# and subject patterns (idempotent upserts).
require_relative "seed_data/financial_catalog_seeder"
FinancialCatalogSeeder.run

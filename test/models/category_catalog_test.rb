# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seeds.rb")

# Verifies the default expense category catalog carries the approved suggested
# savings percentages. The constant is the source of truth for db:seed, so a
# mismatch here means the seed would silently populate the wrong value.
class CategoryCatalogTest < ActiveSupport::TestCase
  EXPECTED_PERCENTAGES = {
    "Mercado" => 5,
    "Restaurantes y cafés" => 10,
    "Domicilios y antojos" => 15,
    "Vivienda y básicos" => 0,
    "Hogar y mejoras" => 5,
    "Servicios y comunicaciones" => 5,
    "Transporte" => 5,
    "Taxis y apps" => 10,
    "Salud" => 0,
    "Cuidado personal" => 5,
    "Ocio y salidas" => 10,
    "Suscripciones" => 15,
    "Compras necesarias" => 0,
    "Gustos y compras" => 15,
    "Educación" => 0,
    "Viajes" => 10,
    "Familia" => 0,
    "Mascotas" => 0,
    "Deudas y cuotas" => 0,
    "Abonos a capital" => 0,
    "Seguros" => 5,
    "Impuestos y trámites" => 0,
    "Trabajo" => nil,
    "Donaciones y regalos" => 5,
    "Otros" => nil
  }.freeze

  test "every seed entry declares a suggested_savings_percentage" do
    missing = EXPENSE_CATEGORY_SEEDS.reject { |attrs| attrs.key?(:suggested_savings_percentage) }
    assert_empty missing.map { |attrs| attrs[:name] }
  end

  test "seed percentages match the approved savings table" do
    by_name = EXPENSE_CATEGORY_SEEDS.index_by { |attrs| attrs[:name] }

    EXPECTED_PERCENTAGES.each do |name, percentage|
      entry = by_name[name]
      assert entry, "expected a seed entry for #{name.inspect}"
      if percentage.nil?
        assert_nil entry[:suggested_savings_percentage],
                   "expected #{name.inspect} to be nil, got #{entry[:suggested_savings_percentage].inspect}"
      else
        assert_equal percentage, entry[:suggested_savings_percentage],
                     "expected #{name.inspect} to carry #{percentage.inspect}, got #{entry[:suggested_savings_percentage].inspect}"
      end
    end
  end

  test "seed entries do not include unexpected categories beyond the table" do
    seeded_names = EXPENSE_CATEGORY_SEEDS.map { |attrs| attrs[:name] }
    assert_equal EXPECTED_PERCENTAGES.keys.sort, seeded_names.sort
  end

  test "seeding writes the percentage to persisted default categories" do
    EXPENSE_CATEGORY_SEEDS.each do |attrs|
      category = Category.find_or_initialize_by(name: attrs[:name], is_default: true, category_type: "expense")
      category.tags = attrs[:tags]
      category.savings_potential = attrs[:savings_potential]
      category.suggested_savings_percentage = attrs[:suggested_savings_percentage]
      category.save!
    end

    EXPECTED_PERCENTAGES.each do |name, percentage|
      persisted = Category.find_by(name: name, is_default: true).suggested_savings_percentage
      percentage.nil? ? assert_nil(persisted, "expected #{name.inspect} to be nil") : assert_equal(percentage, persisted)
    end
  end
end

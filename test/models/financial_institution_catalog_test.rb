# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

# Extensions covering the catalog taxonomy: stable slugs, institution types
# and the seed-ownership policy (no silent re-activation).
class FinancialInstitutionCatalogTest < ActiveSupport::TestCase
  setup do
    FinancialCatalogSeeder.run
  end

  test "every seeded row carries a unique slug and a managed type" do
    slugs = FinancialInstitution.pluck(:slug)
    assert slugs.compact.size == slugs.size
    assert_equal slugs.uniq.size, slugs.size
    assert FinancialInstitution.where.not(institution_type: nil).count >= 40
  end

  test "types taxonomy is bank / digital_bank / digital_wallet / financing_company / other" do
    types = FinancialInstitution.distinct.pluck(:institution_type)
    assert_empty types - FinancialInstitution::TYPES
  end

  test "seed run does NOT re-activate a manually disabled institution" do
    nequi = FinancialInstitution.find_by(slug: "nequi")
    nequi.update!(active: false)

    FinancialCatalogSeeder.run

    nequi.reload
    assert_not nequi.active?
  end

  test "seed run keeps catalog signal attributes (aliases/domains) as source of truth" do
    nequi = FinancialInstitution.find_by(slug: "nequi")

    FinancialCatalogSeeder.run

    nequi.reload
    assert_includes nequi.aliases, "nequi"
    assert_equal "digital_wallet", nequi.institution_type
  end

  test "new entities added to the YAML get created without touching old rows" do
    count = FinancialInstitution.count

    yaml_path = Rails.root.join("db/seed_data/financial_institutions.yml")
    original = File.read(yaml_path)
    extra = [
      "  - canonical_name: Entidad Provisional De Prueba",
      "    slug: entidad-provisional-de-prueba",
      "    institution_type: bank",
      "    aliases: []",
      "    domains: []",
      "    keywords: []",
      "    active: true"
    ].join("\n")
    File.write(yaml_path, original + extra + "\n")
    begin
      FinancialCatalogSeeder.run
      assert_equal count + 1, FinancialInstitution.count
      assert FinancialInstitution.find_by(slug: "entidad-provisional-de-prueba")
    ensure
      File.write(yaml_path, original)
    end
  end

  test "slug validates format and uniqueness; canonical_name stays the readable name" do
    assert_not FinancialInstitution.new(canonical_name: "X", slug: "Nu Colombia").valid?
    assert_not FinancialInstitution.new(canonical_name: "X", slug: "bancolombia").valid?
  end

  test "custom? display contracts differ between catalog and custom entities" do
    assert_not FinancialInstitution.first.custom?
    user = User.create!(name: "Contract User", email: "catalog_contract@example.com", password: "password123")
    custom = user.custom_financial_institutions.create!(name: "La Otra")
    assert custom.custom?
  end
end

# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

class FinancialInstitutionTest < ActiveSupport::TestCase
  setup do
    FinancialCatalogSeeder.run
  end

  test "seeding is idempotent: running twice creates no duplicates" do
    assert_no_difference [ "FinancialInstitution.count", "FinancialKeyword.count", "FinancialSubjectPattern.count" ] do
      FinancialCatalogSeeder.run
    end
  end

  test "seeds the major Colombian institutions with aliases and domains" do
    bancolombia = FinancialInstitution.find_by(canonical_name: "Bancolombia")
    assert_not_nil bancolombia
    assert_includes bancolombia.aliases, "banco de colombia"
    assert_includes bancolombia.domains, "bancolombia.com"
    assert bancolombia.active?

    assert FinancialInstitution.where(active: true).count >= 25
  end

  test "domain matching is accent/case-insensitive and allows subdomains" do
    assert_equal "Davivienda", SourceRecognition::Catalog.match_domain("Mail.DAVIVIENDA.com").canonical_name
    assert_equal "Davivienda", SourceRecognition::Catalog.match_domain("mail.davivienda.com").canonical_name
    assert_nil SourceRecognition::Catalog.match_domain("bancolombia.com.co")
    assert_nil SourceRecognition::Catalog.match_domain("gmail.com")
  end

  test "alias matching finds institutions in free text, accent-insensitively" do
    matched = SourceRecognition::Catalog.match_text("BANCO DAVIVIENDA le informa algo")

    assert_equal [ "Davivienda" ], matched.map(&:canonical_name)
  end

  test "alias matching folds accents (Itaú ~ itau)" do
    matched = SourceRecognition::Catalog.match_text("Banco Itaú transacción aprobada")

    assert_includes matched.map(&:canonical_name), "Banco Itaú"
  end

  test "matched_alias prefers the longest alias" do
    text = SourceRecognition::Catalog.fold("correo de Banco de Bogotá")
    institution = FinancialInstitution.find_by!(canonical_name: "Banco de Bogotá")

    assert_equal "banco de bogota", SourceRecognition::Catalog.matched_alias(text, institution)
  end

  test "keyword matching is word-boundary aware" do
    assert SourceRecognition::TextNormalizer.contains_word?("te notificamos la transacción de hoy", "transacción")
    assert SourceRecognition::TextNormalizer.contains_word?("tarjeta Clasica usada", "clasica")
    refute SourceRecognition::TextNormalizer.contains_word?("supermercado clasimax", "clasica")
    refute SourceRecognition::TextNormalizer.contains_word?("compra en tienda", "compras")
  end

  test "financial keyword weights match their category strength" do
    compra = FinancialKeyword.find_by!(value: "compra")
    tarjeta = FinancialKeyword.find_by!(value: "tarjeta")

    assert_equal "transactions", compra.category
    assert compra.weight > tarjeta.weight
    refute tarjeta.transactional?
    assert compra.transactional?
  end
end

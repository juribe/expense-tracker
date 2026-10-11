# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

class InstitutionsBankMigratorTest < ActiveSupport::TestCase
  setup do
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(canonical_name: "Bancolombia")
    @user = User.create!(name: "Migrator User", email: "migrator@example.com", password: "password123")
    @bancolombia = FinancialInstitution.find_by!(canonical_name: "Bancolombia")
    @bancamia = FinancialInstitution.find_by!(canonical_name: "Bancamía")
    @nequi = FinancialInstitution.find_by!(canonical_name: "Nequi")
  end

  def source!(bank:, kind: "account", active: true, user: @user)
    user.money_sources.create!(name: "Fuente", kind: kind, starting_balance: 0,
                               bank: bank, active: active)
  end

  test "associates sources on an unambiguous catalog match and preserves the bank text" do
    clean = source!(bank: "Bancolombia")
    messy = source!(bank: "  Bancolombia ")
    accented = source!(bank: "Bancamía")
    wallet = source!(bank: "Nequi", kind: "wallet")

    counts = Institutions::BankMigrator.run

    assert_equal @bancolombia.id, clean.reload.institution_id
    assert_equal @bancolombia.id, messy.reload.institution_id
    assert_equal @bancamia.id, accented.reload.institution_id
    assert_equal @nequi.id, wallet.reload.institution_id
    assert_equal 4, counts[:associated]

    # The original free-text bank survives untouched.
    assert_equal "  Bancolombia ", messy.reload.bank
  end

  test "does not associate ambiguous or unmatched bank text" do
    listed = source!(bank: "Bancolombia")
    unknown = source!(bank: "Cooperativa de Mi Barrio")

    counts = Institutions::BankMigrator.run

    assert listed.reload.institution_id.present?
    assert_not unknown.reload.institution_id.present?
    assert_equal "Cooperativa de Mi Barrio", unknown.reload.bank
    assert_equal 1, counts[:unmatched]
  end

  test "inactive institutions still own historical associations" do
    listed = source!(bank: "Nequi")
    @nequi.update!(active: false)

    Institutions::BankMigrator.run

    assert_equal @nequi.id, listed.reload.institution_id
  end

  test "matches the owner's custom institutions by name too" do
    custom = @user.custom_financial_institutions.create!(name: "Caja Torre Alta")
    foreign_user = User.create!(name: "Migrator Foreign", email: "foreign_mig@example.com", password: "password123")
    foreign_custom = foreign_user.custom_financial_institutions.create!(name: "Caja Torre Alta")
    listed = source!(bank: "caja torre alta")
    foreign_source = source!(bank: "caja torre alta", user: foreign_user)

    Institutions::BankMigrator.run

    assert_equal custom.id, listed.reload.institution_id
    assert_equal "CustomFinancialInstitution", listed.reload.institution_type
    assert_equal foreign_custom.id, foreign_source.reload.institution_id
  end

  test "cash and pockets are never auto-bound (reported, text kept)" do
    cash = source!(bank: "Bancolombia", kind: "cash")
    pocket = source!(bank: "Bancolombia", kind: "pocket")

    Institutions::BankMigrator.run

    assert_not cash.reload.institution_id.present?
    assert_not pocket.reload.institution_id.present?
    assert_equal "Bancolombia", cash.reload.bank
  end

  test "dry run reports the plan but writes nothing" do
    listed = source!(bank: "Bancolombia")

    counts = Institutions::BankMigrator.run(dry_run: true)

    assert_equal 1, counts[:associated]
    assert_not listed.reload.institution_id.present?

    Institutions::BankMigrator.run
    assert listed.reload.institution_id.present?
  end

  test "re-runs are idempotent (already-associated sources are skipped)" do
    listed = source!(bank: "Bancolombia")
    unknown = source!(bank: "Cooperativa de Mi Barrio")

    Institutions::BankMigrator.run
    second_counts = Institutions::BankMigrator.run

    assert_equal @bancolombia.id, listed.reload.institution_id
    assert_equal 0, second_counts[:associated]
    assert_equal "Cooperativa de Mi Barrio", unknown.reload.bank
  end
end

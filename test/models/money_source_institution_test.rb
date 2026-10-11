# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

class MoneySourceInstitutionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "MSI User", email: "msi@example.com", password: "password123")
    @other = User.create!(name: "MSI Other", email: "msi_other@example.com", password: "password123")
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(canonical_name: "Bancolombia")
    @bancolombia = FinancialInstitution.find_by(canonical_name: "Bancolombia")
    @nequi = FinancialInstitution.find_by(canonical_name: "Nequi")
  end

  test "institution is optional: cash and unattributed sources keep working" do
    source = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 0)

    assert_not source.institution?
    assert_nil source.institution
    assert_equal "Efectivo", source.display_name
  end

  test "assign_institution_ref attaches a catalog entity by combined ref" do
    source = @user.money_sources.build(name: "Ahorros", kind: "account", starting_balance: 0)
    source.assign_institution_ref("FinancialInstitution:#{@bancolombia.id}")
    assert source.save

    assert_equal @bancolombia.id, source.institution_id
    assert_equal "FinancialInstitution", source.institution_type
    assert_equal "Bancolombia", source.institution_name
  end

  test "assign_institution_ref accepts valid customs and rejects forged foreign ones" do
    mine = @user.custom_financial_institutions.create!(name: "Mi Caja")
    source = @user.money_sources.build(name: "Ahorros Propios", kind: "account", starting_balance: 0)
    source.assign_institution_ref("CustomFinancialInstitution:#{mine.id}")
    assert source.save

    forged = @user.money_sources.build(name: "Robo de entidad", kind: "account", starting_balance: 0)
    foreign = @other.custom_financial_institutions.create!(name: "Caja Ajena")
    forged.assign_institution_ref("CustomFinancialInstitution:#{foreign.id}")
    assert_not forged.save
    assert forged.errors[:institution].any?
  end

  test "assign_institution_ref rejects unknown classes and clears on blank" do
    source = @user.money_sources.build(name: "Faluja", kind: "account", starting_balance: 0)
    source.assign_institution_ref("Sometype:9")
    assert_not source.institution?
    assert_nil source.institution_id

    source.assign_institution_ref(" ")
    assert_not source.institution?
    assert_nil source.institution_id
    assert source.save
  end

  test "display_name prefers the attached entity and falls back to legacy bank" do
    source = @user.money_sources.build(name: "Mi Cuenta", kind: "account", starting_balance: 0, bank: "Banco Viejo")
    assert_equal "Mi Cuenta · Banco Viejo", source.display_name

    source.assign_institution_ref("FinancialInstitution:#{@nequi.id}")
    source.save!
    assert_equal "Mi Cuenta · Nequi", source.display_name
    # Legacy bank text is preserved untouched during the transition.
    assert_equal "Banco Viejo", source.bank
  end

  test "inactive global entities keep historical associations and remain selectable in edit" do
    @nequi.update!(active: false)
    source = @user.money_sources.create!(name: "Nequi",
                                         kind: "wallet",
                                         starting_balance: 0,
                                         institution_type: "FinancialInstitution",
                                         institution_id: @nequi.id)

    source.reload
    assert_equal @nequi.id, source.institution_id
    assert_equal "Nequi", source.institution_name
  end

  test "institution_name reads the CACHED column without loading the entity" do
    source = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 0)
    source.assign_institution_ref("FinancialInstitution:#{@bancolombia.id}")
    source.save!

    assert_equal "Bancolombia", source.reload.institution_cached_name
    # Detached snapshot reads work with the association object evicted.
    source.reload
    assert_equal "Bancolombia", source.institution_name
  end

  test "cache is written on attach and cleared on detach (write path only)" do
    source = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 0,
                                         institution_type: "FinancialInstitution",
                                         institution_id: @bancolombia.id)
    assert_equal "Bancolombia", source.reload.institution_cached_name

    source.assign_institution_ref("")
    source.save!
    source.reload
    assert_nil source.institution_cached_name
    assert_equal "Ahorros", source.display_name
  end

  test "no association candidates: unattached rows fall back to the legacy bank" do
    source = @user.money_sources.create!(name: "Vieja", kind: "account", starting_balance: 0, bank: "Banco Viejo")

    assert_nil source.institution_cached_name
    assert_equal "Banco Viejo", source.institution_name
  end

  test "several sources of the same entity share it (no copies)" do
    3.times do |i|
      @user.money_sources.create!(name: "Producto #{i}", kind: "account", starting_balance: 0,
                                  institution_type: "FinancialInstitution",
                                  institution_id: @bancolombia.id)
    end

    assert_equal 3, @user.money_sources.where(institution_type: "FinancialInstitution",
                                              institution_id: @bancolombia.id).count
  end

  test "institution_aliases folds catalog aliases attached and bank fallback unattached" do
    source = @user.money_sources.build(name: "X", kind: "account", starting_balance: 0, bank: "Bancamía")
    assert_includes source.institution_aliases, "bancamia"

    source.assign_institution_ref("FinancialInstitution:#{@bancolombia.id}")
    source.save!

    aliases = source.institution_aliases
    assert_includes aliases, "banco de colombia"
    assert_includes aliases, "bancolombia"
  end
end

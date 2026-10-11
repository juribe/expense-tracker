# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

# Rename cascade: whenever an entity (global or custom) changes its display
# name, the denormalized labels on the referencing money sources must follow
# so views keep rendering fresh values without touching the entity tables.
class InstitutionCachedNameCascadeTest < ActiveSupport::TestCase
  setup do
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(canonical_name: "Bancolombia")
    @user = User.create!(name: "Cascade User", email: "cascade@example.com", password: "password123")
    @bancolombia = FinancialInstitution.find_by!(canonical_name: "Bancolombia")
  end

  def attach_source(user, institution_type: "FinancialInstitution", institution_id:)
    user.money_sources.create!(name: "Fuente", kind: "account", starting_balance: 0,
                               institution_type: institution_type,
                               institution_id: institution_id)
  end

  test "renaming a global institution cascades the cached name to all its sources" do
    one = attach_source(@user, institution_id: @bancolombia.id)
    two = attach_source(@user, institution_id: @bancolombia.id)

    @bancolombia.update!(canonical_name: "Bancolombia", slug: @bancolombia.slug) # no-op must not churn
    @bancolombia.update!(canonical_name: "Bancolombia S.A.")

    assert_equal "Bancolombia S.A.", one.reload.institution_cached_name
    assert_equal "Bancolombia S.A.", two.reload.institution_cached_name
    assert_equal "Fuente · Bancolombia S.A.", one.reload.display_name
  end

  test "renaming a custom entity cascades only to the owner's sources" do
    other = User.create!(name: "Cascade Other", email: "cascade_other@example.com", password: "password123")
    custom = @user.custom_financial_institutions.create!(name: "Caja Vecina")
    mine = attach_source(@user, institution_type: "CustomFinancialInstitution", institution_id: custom.id)

    custom.update!(name: "Caja Vecina Renombrada")

    assert_equal "Caja Vecina Renombrada", mine.reload.institution_cached_name
    assert_empty other.money_sources
  end

  test "deactivating an institution does NOT change cached names" do
    listed = attach_source(@user, institution_id: @bancolombia.id)
    initial = listed.reload.institution_cached_name

    @bancolombia.update!(active: false)

    assert_equal initial, listed.reload.institution_cached_name
  end

  test "detaching a source clears the cache; re-associating rewrites it" do
    listed = attach_source(@user, institution_id: @bancolombia.id)
    nequi = FinancialInstitution.find_by!(canonical_name: "Nequi")

    listed.assign_institution_ref("FinancialInstitution:#{nequi.id}")
    listed.save!
    assert_equal "Nequi", listed.reload.institution_cached_name

    listed.assign_institution_ref("")
    listed.save!
    assert_nil listed.reload.institution_cached_name
  end

  test "BankMigrator attaches through the callback so the cache is written too" do
    listed = @user.money_sources.create!(name: "Fuente", kind: "account", starting_balance: 0, bank: "Bancolombia")

    Institutions::BankMigrator.run

    assert_equal "Bancolombia", listed.reload.institution_cached_name
  end
end

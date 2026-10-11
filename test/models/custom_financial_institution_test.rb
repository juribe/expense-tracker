# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

class CustomFinancialInstitutionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Custom Inst User", email: "custom_inst@example.com", password: "password123")
    @other = User.create!(name: "Other User", email: "other_custom_inst@example.com", password: "password123")
  end

  test "belongs to a user and validates name presence and uniqueness per user" do
    institution = @user.custom_financial_institutions.create!(name: "Mi Cooperativa")
    assert institution.persisted?

    duplicate = @user.custom_financial_institutions.build(name: "  mi cooperativa  ")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?

    # Same name for ANOTHER user is fine: customs are per-user.
    assert @other.custom_financial_institutions.build(name: "Mi Cooperativa").valid?
  end

  test "validates institution_type against the catalog taxonomy" do
    assert @user.custom_financial_institutions.build(name: "Alpha", institution_type: "bank").valid?
    assert @user.custom_financial_institutions.build(name: "Beta", institution_type: "nope").invalid?
    assert @user.custom_financial_institutions.build(name: "Gamma", institution_type: nil).valid?
  end

  test "customs are private: scoped per user for every consumer" do
    mine = @user.custom_financial_institutions.create!(name: "Privada")
    theirs = @other.custom_financial_institutions.create!(name: "Ajena")

    assert_includes @user.custom_financial_institutions.pluck(:id), mine.id
    assert_not_includes @user.custom_financial_institutions.pluck(:id), theirs.id
  end

  test "a custom entity can back several money sources of the same user" do
    institution = @user.custom_financial_institutions.create!(name: " grandma bank")
    2.times { |i| @user.money_sources.create!(name: "Cuenta #{i}", kind: "account", starting_balance: 0,
                                              institution_type: "CustomFinancialInstitution",
                                              institution_id: institution.id) }

    assert_equal 2, institution.money_sources.count
  end

  test "is never a global catalog row" do
    FinancialCatalogSeeder.run
    before = FinancialInstitution.count
    @user.custom_financial_institutions.create!(name: "Nueva Marca Rara")

    FinancialCatalogSeeder.run
    assert_equal before, FinancialInstitution.count
    assert_nil FinancialInstitution.find_by(canonical_name: "Nueva Marca Rara")
  end
end

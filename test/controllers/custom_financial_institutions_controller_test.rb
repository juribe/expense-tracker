# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

# Ownership lives in the controllers (current_user scoping): one user can
# never see, edit or delete another user's custom entity.
class CustomFinancialInstitutionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "CFI User", email: "cfi_ctrl@example.com",
                         password: "password123")
    @other = User.create!(name: "CFI Other", email: "cfi_ctrl_other@example.com", password: "password123")
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(canonical_name: "Bancolombia")
    sign_in @user
  end

  test "creates a new custom entity for the current user only" do
    assert_difference "@user.custom_financial_institutions.count" do
      post custom_financial_institutions_path, params: {
        custom_financial_institution: { name: "Mi Cooperativa", institution_type: "other" }
      }
    end

    assert_equal @user.custom_financial_institutions.order(:id).last.name, "Mi Cooperativa"
    assert_empty @other.custom_financial_institutions.where(name: "Mi Cooperativa")
  end

  test "another user's entity 404s" do
    foreign = @other.custom_financial_institutions.create!(name: "Cada Ajena")

    get edit_custom_financial_institution_path(foreign)
    assert_response :not_found

    patch custom_financial_institution_path(foreign), params: { custom_financial_institution: { name: "Robado" } }
    assert_response :not_found
    assert_equal "Cada Ajena", foreign.reload.name
  end

  test "delete a referenced entity is blocked so no source dangles" do
    institution = @user.custom_financial_institutions.create!(name: "Usada")
    @user.money_sources.create!(name: "Asociada", kind: "account", starting_balance: 0,
                                institution_type: "CustomFinancialInstitution",
                                institution_id: institution.id)

    assert_no_difference "CustomFinancialInstitution.count" do
      delete custom_financial_institution_path(institution)
    end

    assert institution.reload.persisted?
  end

  test "free delete removes the entity (and only its owner's row)" do
    institution = @user.custom_financial_institutions.create!(name: "Libre")
    foreign = @other.custom_financial_institutions.create!(name: "Ajena")

    assert_difference "CustomFinancialInstitution.count", -1 do
      delete custom_financial_institution_path(institution)
    end

    assert_not CustomFinancialInstitution.exists?(institution.id)
    assert CustomFinancialInstitution.exists?(foreign.id)
  end
end

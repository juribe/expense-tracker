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

  test "new and edit render the shared card header and footer" do
    institution = @user.custom_financial_institutions.create!(name: "Mi Cooperativa", institution_type: "other")

    get new_custom_financial_institution_path
    assert_response :success
    assert_select "form[action='#{custom_financial_institutions_path}'] .card" do
      assert_select ".card-header .icon-chip i.ti-building-bank"
      assert_select ".card-header h4", text: "Nueva entidad propia"
      assert_select ".card-header .card-subtitle", text: /Agrega una entidad/
      assert_select ".card-footer a.btn.btn-outline-secondary[href=?]", financial_institutions_path, text: "Cancelar"
      assert_select ".card-footer input[type=submit].btn.btn-primary"
    end

    get edit_custom_financial_institution_path(institution)
    assert_response :success
    assert_select "form[action='#{custom_financial_institution_path(institution)}'] .card .card-header h4", text: "Editar entidad propia"
    assert_select "form[action='#{custom_financial_institution_path(institution)}'] .card .card-footer a.btn.btn-outline-secondary[href=?]", financial_institutions_path
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

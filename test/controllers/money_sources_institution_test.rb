# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

# Controller security for the institution controls of money sources: scoping,
# ownership re-checks and polymorphic ref parsing.
class MoneySourcesInstitutionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(canonical_name: "Bancolombia")
    @user = User.create!(
      name: "MSI User",
      email: "msi_ctrl@example.com",
      password: "password123"
    )
    @other = User.create!(name: "MSI Other", email: "msi_ctrl_other@example.com", password: "password123")
    @bancolombia = FinancialInstitution.find_by!(canonical_name: "Bancolombia")
    sign_in @user
  end

  test "create attaches the selected catalog entity via institution_ref" do
    assert_difference "MoneySource.count", 1 do
      post money_sources_path, params: {
        money_source: {
          name: "Nueva Cuenta", kind: "account", starting_balance: "0",
          institution_ref: "FinancialInstitution:#{@bancolombia.id}"
        }
      }
    end

    source = MoneySource.order(:id).last
    assert_equal @bancolombia.id, source.institution_id
    assert_equal "Bancolombia", source.institution_name
  end

  test "a forged custom institution ref owned by another user is rejected" do
    foreign = @other.custom_financial_institutions.create!(name: "Caja Ajena")

    assert_no_difference "MoneySource.count" do
      post money_sources_path, params: {
        money_source: {
          name: "Robo", kind: "account", starting_balance: "0",
          institution_ref: "CustomFinancialInstitution:#{foreign.id}"
        }
      }
    end
  end

  test "the form renders the institution autocomplete with catalog options" do
    get new_money_source_path
    assert_response :success

    assert_select "input[type=hidden][name='money_source[institution_ref]']"
    assert_select "[data-institution-search]"

    options_json = response.body[/data-options="([^"]*)"/, 1]
    assert_not_nil options_json
    payload = JSON.parse(CGI.unescapeHTML(options_json))
    assert payload["options"].any? { |option| option["value"] == "FinancialInstitution:#{@bancolombia.id}" }
    assert_not payload.key?("groups")
    assert_equal "Banco", payload["types"]["bank"]
  end

  test "edit form keeps the currently attached entity selected" do
    source = @user.money_sources.create!(name: "Editable", kind: "account", starting_balance: 0,
                                         institution_type: "FinancialInstitution",
                                         institution_id: @bancolombia.id)
    get edit_money_source_path(source)
    assert_response :success
    assert_select "input[name='money_source[institution_ref]'][value=?]",
                  "FinancialInstitution:#{@bancolombia.id}"
  end

  test "update attaches, changes and clears the institution" do
    source = @user.money_sources.create!(name: "Editable", kind: "account", starting_balance: 0, bank: "Viejo")

    patch money_source_path(source), params: {
      money_source: { institution_ref: "FinancialInstitution:#{@bancolombia.id}" }
    }
    assert_equal @bancolombia.id, source.reload.institution_id

    patch money_source_path(source), params: { money_source: { institution_ref: "" } }
    assert_equal "Viejo", source.reload.bank
    assert_nil source.reload.institution_id
  end

  test "the entities hub renders only the user's custom entities (no catalog)" do
    custom = @user.custom_financial_institutions.create!(name: "Mi Caja")
    @other.custom_financial_institutions.create!(name: "Caja Ajena")

    get financial_institutions_path
    assert_response :success

    assert_select "[data-testid=custom-institution-row]", text: /Mi Caja/
    assert_select "body", text: /Caja Ajena/, count: 0
    assert_select "body", text: /#{@bancolombia.canonical_name}/, count: 0
  end

  test "entities hub requires authentication" do
    sign_out @user
    get financial_institutions_path
    assert_redirected_to new_user_session_path
  end
end

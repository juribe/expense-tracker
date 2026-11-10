# frozen_string_literal: true

require "test_helper"

# "Mis entidades" is a UI-only hub over the user's custom institutions. These
# tests pin the redesigned card markup, the search controls and the note while
# confirming the existing edit/delete endpoints are the ones wired up.
class FinancialInstitutionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Entities UI", email: "entities-ui@example.com",
                         password: "password123")
    @other = User.create!(name: "Entities Other", email: "entities-ui-other@example.com",
                          password: "password123")
    sign_in @user
  end

  test "renders the redesigned header, search and informational note" do
    get financial_institutions_path

    assert_response :success
    assert_select ".page-header .page-title", text: "Mis entidades"
    assert_select ".page-header .page-subtitle",
                  text: "Tus propias entidades financieras. Agrega instituciones que no encuentres en el catálogo compartido de Yogasto."
    assert_select "input[type=search][data-financial-institution-search][placeholder=?]",
                  "Buscar entidad..."
    assert_select ".category-toolbar", text: /Entidades personalizadas de tu cuenta/
    assert_select ".category-note i.ti-info-circle"
    assert_select ".category-note strong", text: "Sobre tus entidades propias"
    assert_select ".category-note p",
                  text: "Estas entidades complementan el catálogo compartido. Puedes asociarlas a tus fuentes de dinero cuando corresponda."
  end

  test "renders the user's entities as compact cards with their real type and existing actions" do
    wise = @user.custom_financial_institutions.create!(name: "Wise", institution_type: "digital_bank")
    @user.custom_financial_institutions.create!(name: "Cooperativa ejemplo", institution_type: "other")
    @other.custom_financial_institutions.create!(name: "Entidad ajena", institution_type: "bank")

    get financial_institutions_path

    assert_response :success
    assert_select "[data-financial-institution-card]", count: 2
    assert_select "[data-financial-institution-card][data-entity-name='Wise']" do
      assert_select ".entity-card__avatar", text: "W"
      assert_select ".entity-card__name", text: "Wise"
      assert_select ".entity-card__type", text: "Banco digital"
      assert_select ".entity-card__actions a.btn.btn-sm.btn-outline-primary[href=?]",
                    edit_custom_financial_institution_path(wise)
      assert_select ".entity-card__actions form[action=?] button.btn.btn-sm.btn-outline-danger",
                    custom_financial_institution_path(wise)
    end
    assert_select "[data-entity-name='Cooperativa ejemplo'] .entity-card__type",
                  text: "Otra entidad financiera"
    assert_select "body", text: /Entidad ajena/, count: 0
    assert_select ".category-card__tag", count: 0
    assert_select ".badge", count: 0
  end

  test "renders a responsive three-two-one column grid" do
    @user.custom_financial_institutions.create!(name: "Wise", institution_type: "digital_bank")

    get financial_institutions_path

    assert_select "[data-financial-institutions-grid] > .col-12.col-md-6.col-lg-4", count: 1
  end

  test "shows the empty state and the new-entity call to action when there are no customs" do
    get financial_institutions_path

    assert_response :success
    assert_select "[data-financial-institution-card]", count: 0
    assert_select ".empty-state", text: /Aún no tienes entidades propias/
    assert_select ".empty-state a.btn.btn-primary[href=?]", new_custom_financial_institution_path
  end
end

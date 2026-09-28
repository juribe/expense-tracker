# frozen_string_literal: true

require "test_helper"

class RecurringTemplatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Recurring Ctrl User",
      email: "recurring_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
    @account = @user.money_sources.create!(name: "Cuenta", kind: "account")
    @card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card")
    @loan = @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")
  end

  test "GET /recurring_templates (income) offers only payment sources" do
    get recurring_templates_path(kind: "income")
    assert_response :success

    offered = @user.money_sources.active.payment_sources.to_a.map(&:id)
    assert_select "select[name='recurring_template[money_source_id]'] option" do |options|
      values = options.map { |o| o["value"] }
      offered.each { |id| assert_includes values, id.to_s }
      assert_not_includes values, @loan.id.to_s
    end
  end

  test "GET /recurring_templates (expense) keeps loans for debt-payment cuotas" do
    get recurring_templates_path(kind: "expense")
    assert_response :success

    assert_select "select[name='recurring_template[money_source_id]'] option" do |options|
      values = options.map { |o| o["value"] }
      assert_includes values, @account.id.to_s
      assert_includes values, @card.id.to_s
      # The wizard-backed debt-payment cuota points at the loan itself.
      assert_includes values, @loan.id.to_s
    end
  end
end

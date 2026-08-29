# frozen_string_literal: true

require "test_helper"

class MoneySourcesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "money_sources_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  def create_source(name: "My Account", kind: "account", **opts)
    @user.money_sources.create!({ name: name, kind: kind, starting_balance: 0 }.merge(opts))
  end

  test "GET /money_sources renders the index" do
    create_source
    get money_sources_path
    assert_response :success
    assert_select "h1", text: I18n.t("nav.money_sources")
  end

  test "GET /money_sources shows empty state when no sources" do
    get money_sources_path
    assert_response :success
    assert_select "[data-testid]", count: 0
  end

  test "GET /money_sources/new renders the form" do
    get new_money_source_path
    assert_response :success
    assert_select "form"
  end

  test "POST /money_sources creates a money source" do
    assert_difference "MoneySource.count", 1 do
      post money_sources_path, params: {
        money_source: { name: "New Account", kind: "account", starting_balance: 500 }
      }
    end
    assert_redirected_to money_sources_path
    follow_redirect!
    assert_equal I18n.t("money_sources.flashes.created"), flash[:notice]
  end

  test "POST /money_sources creates with identifiers" do
    assert_difference "MoneySource.count", 1 do
      assert_difference "MoneySourceIdentifier.count", 1 do
        post money_sources_path, params: {
          money_source: { name: "Visa", kind: "credit_card" },
          identifiers: [{ kind: "card_last_four", value: "1234" }]
        }
      end
    end
    source = MoneySource.last
    assert_equal "1234", source.identifiers.first.value
  end

  test "POST /money_sources renders new on validation failure" do
    post money_sources_path, params: {
      money_source: { name: "", kind: "account" }
    }
    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "GET /money_sources/:id renders show" do
    source = create_source
    get money_source_path(source)
    assert_response :success
  end

  test "GET /money_sources/:id/edit renders edit form" do
    source = create_source
    get edit_money_source_path(source)
    assert_response :success
    assert_select "form"
  end

  test "PATCH /money_sources/:id updates the money source" do
    source = create_source
    patch money_source_path(source), params: {
      money_source: { name: "Updated Name" }
    }
    assert_redirected_to money_sources_path
    assert_equal "Updated Name", source.reload.name
  end

  test "PATCH /money_sources/:id updates identifiers" do
    source = create_source
    source.identifiers.create!(kind: "card_last_four", value: "1111")

    patch money_source_path(source), params: {
      money_source: { name: source.name },
      identifiers: [{ kind: "card_last_four", value: "9999" }]
    }
    assert_equal 1, source.reload.identifiers.count
    assert_equal "9999", source.identifiers.first.value
  end

  test "PATCH /money_sources/:id removes identifiers when blank" do
    source = create_source
    source.identifiers.create!(kind: "card_last_four", value: "1111")

    patch money_source_path(source), params: {
      money_source: { name: source.name },
      identifiers: []
    }
    assert_equal 0, source.reload.identifiers.count
  end

  test "DELETE /money_sources/:id destroys the money source" do
    source = create_source
    assert_difference "MoneySource.count", -1 do
      delete money_source_path(source)
    end
    assert_redirected_to money_sources_path
  end

  test "user cannot access other user's money source" do
    other_user = User.create!(name: "Other", email: "other_money_src_ctrl@example.com", password: "password123")
    other_source = other_user.money_sources.create!(name: "Other Source", kind: "account")
    get money_source_path(other_source)
    assert_response :not_found
  end
end

# frozen_string_literal: true

require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = create_user(email: "admin-users-#{SecureRandom.hex(6)}@example.com", admin: true)
    @admin.confirm
    sign_in @admin
  end

  test "non-admin users cannot open the users list" do
    sign_out :user
    sign_in regular_user

    get admin_users_path

    assert_redirected_to root_path
    assert_equal I18n.t("errors.not_authorized"), flash[:alert]
  end

  test "non-admin users cannot delete accounts" do
    target = create_user(email: "target-by-non-admin-#{SecureRandom.hex(6)}@example.com")
    sign_out :user
    sign_in regular_user

    assert_no_difference -> { User.count } do
      delete admin_user_path(target)
    end

    assert_redirected_to root_path
    assert User.exists?(target.id)
  end

  test "admin sees email, verification status, creation date and money source count" do
    verified = create_user(email: "verified-user-#{SecureRandom.hex(6)}@example.com")
    verified.confirm
    verified.money_sources.create!(name: "Cuenta", kind: "account")
    verified.money_sources.create!(name: "Efectivo", kind: "cash")
    pending = create_user(email: "pending-user-#{SecureRandom.hex(6)}@example.com")

    get admin_users_path

    assert_response :success
    assert_select "tr[data-testid='admin-user-row'][data-user-id='#{verified.id}']" do
      assert_select "td[data-testid='user-email'] .fw-semibold", text: verified.email
      assert_select "[data-testid='user-verified']", text: I18n.t("admin.users.verified", default: "Verificado")
      assert_select "[data-testid='user-created-at']", text: I18n.l(verified.created_at, format: :short)
      assert_select "[data-testid='user-accounts-count']", text: "2"
    end

    assert_select "tr[data-testid='admin-user-row'][data-user-id='#{pending.id}']" do
      assert_select "[data-testid='user-pending']", text: I18n.t("admin.users.pending", default: "Pendiente")
      assert_select "[data-testid='user-accounts-count']", text: "0"
    end
  end

  test "admin deletes a user" do
    target = create_user(email: "deleted-user-#{SecureRandom.hex(6)}@example.com")

    assert_difference -> { User.count }, -1 do
      delete admin_user_path(target)
    end

    assert_redirected_to admin_users_path
    assert_equal I18n.t("admin.users.deleted", default: "Usuario eliminado."), flash[:notice]
    refute User.exists?(target.id)
  end

  test "admin cannot delete their own account" do
    assert_no_difference -> { User.count } do
      delete admin_user_path(@admin)
    end

    assert_redirected_to admin_users_path
    assert_equal I18n.t("admin.users.cannot_delete_self", default: "No puedes eliminar tu propia cuenta."), flash[:alert]
    assert User.exists?(@admin.id)
  end

  test "admin bulk delete removes users with webauthn credentials" do
    first = create_user(email: "bulk-webauthn-one-#{SecureRandom.hex(6)}@example.com")
    second = create_user(email: "bulk-webauthn-two-#{SecureRandom.hex(6)}@example.com")
    [ first, second ].each_with_index do |user, index|
      user.webauthn_credentials.create!(
        external_id: "bulk-webauthn-#{index}-#{SecureRandom.hex(6)}",
        public_key: "public-key",
        name: "Passkey",
        sign_count: 0,
        authentication_factor: :first_factor
      )
      source = user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 10_000)
      2.times do
        user.transactions.create!(amount: 1_000, date: Date.current, kind: "expense",
                                  source: "manual", money_source: source)
      end
    end

    assert_difference -> { User.count }, -2 do
      delete bulk_destroy_admin_users_path, params: { user_ids: [ first.id, second.id ] }
    end

    assert_redirected_to admin_users_path
    refute User.exists?(first.id)
    refute User.exists?(second.id)
  end

  test "non-admin users cannot bulk delete accounts" do
    first = create_user(email: "bulk-target-one-#{SecureRandom.hex(6)}@example.com")
    second = create_user(email: "bulk-target-two-#{SecureRandom.hex(6)}@example.com")
    sign_out :user
    sign_in regular_user

    assert_no_difference -> { User.count } do
      delete bulk_destroy_admin_users_path, params: { user_ids: [ first.id, second.id ] }
    end

    assert_redirected_to root_path
    assert User.exists?(first.id)
    assert User.exists?(second.id)
  end

  test "admin bulk deletes the selected users" do
    first = create_user(email: "bulk-delete-one-#{SecureRandom.hex(6)}@example.com")
    second = create_user(email: "bulk-delete-two-#{SecureRandom.hex(6)}@example.com")
    kept = create_user(email: "bulk-kept-#{SecureRandom.hex(6)}@example.com")

    assert_difference -> { User.count }, -2 do
      delete bulk_destroy_admin_users_path, params: { user_ids: [ first.id, second.id ] }
    end

    assert_redirected_to admin_users_path
    assert_equal I18n.t("admin.users.bulk.deleted", count: 2, default: "2 usuarios eliminados."), flash[:notice]
    refute User.exists?(first.id)
    refute User.exists?(second.id)
    assert User.exists?(kept.id)
  end

  test "admin bulk delete ignores their own account" do
    target = create_user(email: "bulk-self-target-#{SecureRandom.hex(6)}@example.com")

    assert_difference -> { User.count }, -1 do
      delete bulk_destroy_admin_users_path, params: { user_ids: [ @admin.id, target.id ] }
    end

    assert_redirected_to admin_users_path
    assert User.exists?(@admin.id)
    refute User.exists?(target.id)
  end

  test "admin bulk delete without a selection changes nothing" do
    assert_no_difference -> { User.count } do
      delete bulk_destroy_admin_users_path, params: { user_ids: [ "" ] }
    end

    assert_redirected_to admin_users_path
    assert_equal I18n.t("admin.users.bulk.none_selected", default: "Selecciona al menos un usuario."), flash[:alert]
  end

  private

  def create_user(email:, admin: false)
    User.create!(
      name: "Admin Users Test #{SecureRandom.hex(2)}",
      email: email,
      password: "password123",
      admin: admin
    )
  end

  def regular_user
    @regular_user ||= create_user(email: "regular-admin-users-#{SecureRandom.hex(6)}@example.com")
  end
end

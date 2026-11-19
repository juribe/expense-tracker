# frozen_string_literal: true

require "application_system_test_case"

# The admin users page selects several accounts with checkboxes and deletes
# them in one bulk action. The admin's own account is never selectable.
class AdminUsersBulkDeleteTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    page.current_window.resize_to(1400, 1000)

    @admin = User.create!(name: "Bulk Admin", email: "bulk-admin-#{SecureRandom.hex(4)}@example.com",
                          password: "password123", admin: true)
    @admin.confirm
    @first = User.create!(name: "Bulk One", email: "bulk-one-#{SecureRandom.hex(4)}@example.com",
                          password: "password123")
    @second = User.create!(name: "Bulk Two", email: "bulk-two-#{SecureRandom.hex(4)}@example.com",
                           password: "password123")
  end

  test "select all enables bulk delete and removes the selected accounts" do
    sign_in
    visit admin_users_path

    assert_selector "tr[data-testid='admin-user-row']", count: 3
    assert_selector "[data-admin-users-bulk-submit][disabled]"
    assert_selector "tr[data-user-id='#{@admin.id}'] input[data-admin-users-checkbox][disabled]"
    assert_equal "hidden", page.evaluate_script("getComputedStyle(document.querySelector('.table-responsive')).overflowY")

    find("[data-admin-users-select-all]").check

    assert_selector "[data-admin-users-selected-count]", text: "2"
    assert_no_selector "[data-admin-users-bulk-submit][disabled]"

    find("[data-admin-users-bulk-submit]").click
    wait_for_modal_transition("[data-testid='dialog-modal']")
    find("[data-testid='dialog-accept']").click

    assert_selector "tr[data-user-id='#{@admin.id}']"
    assert_no_selector "tr[data-user-id='#{@first.id}']"
    assert_no_selector "tr[data-user-id='#{@second.id}']"
  end

  private

  def sign_in
    visit new_user_session_path
    fill_in "user_email", with: @admin.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

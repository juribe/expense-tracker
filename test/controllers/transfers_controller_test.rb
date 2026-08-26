# frozen_string_literal: true

require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "transfers_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
    @savings = @user.money_sources.create!(name: "Savings", kind: "account", starting_balance: 1000)
    @checking = @user.money_sources.create!(name: "Checking", kind: "account", starting_balance: 0)
  end

  def create_transfer(amount: 100)
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: amount, date: Date.today)
  end

  test "GET /transfers renders the index" do
    create_transfer
    get transfers_path
    assert_response :success
    assert_select "h1", text: /Transfers/
  end

  test "GET /transfers shows empty state when no transfers" do
    get transfers_path
    assert_response :success
  end

  test "GET /transfers/new renders the form" do
    get new_transfer_path
    assert_response :success
    assert_select "form"
    assert_select "select", minimum: 2
  end

  test "POST /transfers creates a transfer" do
    assert_difference "Transfer.count", 1 do
      post transfers_path, params: {
        transfer: {
          from_source_id: @savings.id,
          to_source_id: @checking.id,
          amount: 200,
          date: Date.today.to_s,
          note: "Monthly transfer"
        }
      }
    end
    assert_redirected_to transfers_path
    follow_redirect!
    assert_equal "Transfer was successfully created.", flash[:notice]
  end

  test "POST /transfers renders new on validation failure" do
    post transfers_path, params: {
      transfer: {
        from_source_id: @savings.id,
        to_source_id: @savings.id,
        amount: 100,
        date: Date.today.to_s
      }
    }
    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "DELETE /transfers/:id destroys the transfer" do
    transfer = create_transfer
    assert_difference "Transfer.count", -1 do
      delete transfer_path(transfer)
    end
    assert_redirected_to transfers_path
  end

  test "transfer affects balances correctly" do
    create_transfer(amount: 200)
    assert_equal BigDecimal("800"), @savings.reload.balance
    assert_equal BigDecimal("200"), @checking.reload.balance
  end

  test "user cannot delete other user's transfer" do
    other_user = User.create!(name: "Other", email: "other_transfer_ctrl@example.com", password: "password123")
    other_a = other_user.money_sources.create!(name: "A", kind: "account")
    other_b = other_user.money_sources.create!(name: "B", kind: "account")
    other_transfer = Transfer.create!(user: other_user, from_source: other_a, to_source: other_b, amount: 50, date: Date.today)
    delete transfer_path(other_transfer)
    assert_response :not_found
    assert Transfer.exists?(other_transfer.id)
  end
end

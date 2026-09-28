# frozen_string_literal: true

require "test_helper"

# WhatsappConnection: the current active link between a user and a WhatsApp
# identity. Disconnection must be reversible for the same user and must never
# delete expenses, financial data or the identity itself.
class WhatsappConnectionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Conn User", email: "conn_user@example.com", password: "password123")
    @identity = WhatsappIdentity.create!(phone_number: "573001234567", claimed_by_user: @user, claimed_at: Time.current)
  end

  test "active? is true until disconnected_at is set" do
    connection = WhatsappConnection.create!(user: @user, whatsapp_identity: @identity, connected_at: Time.current)

    assert connection.active?
    connection.disconnect!
    assert_not connection.active?
    assert connection.disconnected_at.present?
  end

  test "an identity can have at most one active connection" do
    WhatsappConnection.create!(user: @user, whatsapp_identity: @identity, connected_at: Time.current)

    second = WhatsappConnection.new(user: @user, whatsapp_identity: @identity, connected_at: Time.current)
    assert_not second.valid?
  end

  test "a new active connection is allowed after disconnecting" do
    first = WhatsappConnection.create!(user: @user, whatsapp_identity: @identity, connected_at: Time.current)
    first.disconnect!

    second = WhatsappConnection.new(user: @user, whatsapp_identity: @identity, connected_at: Time.current)
    assert second.valid?
  end

  test "disconnect! keeps the user's expenses" do
    category = Category.find_by(name: "Restaurants") ||
               Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    expense = @user.expenses.create!(description: "Almuerzo", amount: 50_000, date: Date.current, category: category)
    connection = WhatsappConnection.create!(user: @user, whatsapp_identity: @identity, connected_at: Time.current)

    connection.disconnect!

    assert Expense.exists?(expense.id)
  end

  test "disconnect! keeps the identity claim intact" do
    connection = WhatsappConnection.create!(user: @user, whatsapp_identity: @identity, connected_at: Time.current)

    connection.disconnect!

    assert WhatsappIdentity.exists?(@identity.id)
    assert_equal @user.id, @identity.reload.claimed_by_user_id
  end
end

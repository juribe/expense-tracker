# frozen_string_literal: true

require "test_helper"

class FinancialChatTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Test User",
      email: "chat_model_test@example.com",
      password: "password123"
    )
  end

  test "belongs to user" do
    chat = FinancialChat.new(user: @user)
    assert chat.save
    assert_equal @user.id, chat.user_id
  end

  test "requires a user" do
    chat = FinancialChat.new
    assert_not chat.valid?
    assert chat.errors[:user].present?
  end

  test "only one chat per user" do
    @user.create_financial_chat!
    second = FinancialChat.new(user: @user)
    assert_not second.valid?
    assert second.errors[:user_id].present?
  end

  test "for_user returns existing chat or creates one" do
    assert_equal FinancialChat.count, 0
    chat = FinancialChat.for_user(@user)
    assert chat.persisted?
    assert_equal @user.id, chat.user_id
    assert_equal chat.id, FinancialChat.for_user(@user).id
    assert_equal FinancialChat.count, 1
  end

  test "messages are ordered oldest first" do
    chat = FinancialChat.for_user(@user)
    first = chat.messages.create!(role: "user", content: "First question")
    second = chat.messages.create!(role: "assistant", content: "First answer")
    assert_equal [ first.id, second.id ], chat.messages.reload.map(&:id)
  end

  test "conversation_history returns role/content pairs excluding system" do
    chat = FinancialChat.for_user(@user)
    chat.messages.create!(role: "user", content: "How much did I spend?")
    chat.messages.create!(role: "assistant", content: "COP 2,340,000")

    history = chat.conversation_history
    assert_equal 2, history.size
    assert_equal [ { role: "user", content: "How much did I spend?" },
                   { role: "assistant", content: "COP 2,340,000" } ], history
  end
end

# frozen_string_literal: true

require "test_helper"

class FinancialChatMessageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Test User",
      email: "chat_message_test@example.com",
      password: "password123"
    )
    @chat = FinancialChat.for_user(@user)
  end

  test "requires role and content" do
    message = @chat.messages.new(role: "user")
    assert_not message.valid?
    assert message.errors[:content].present?
  end

  test "only accepts user and assistant roles" do
    message = @chat.messages.new(role: "system", content: "nope")
    assert_not message.valid?
    assert message.errors[:role].present?
  end

  test "only accepts known statuses" do
    message = @chat.messages.new(role: "user", content: "hi", status: "bogus")
    assert_not message.valid?
  end

  test "default status is complete" do
    message = @chat.messages.create!(role: "user", content: "hi")
    assert_equal "complete", message.status
  end

  test "user? and assistant? helpers" do
    user_message = @chat.messages.create!(role: "user", content: "hi")
    assistant_message = @chat.messages.create!(role: "assistant", content: "hello")
    assert user_message.user?
    assert_not user_message.assistant?
    assert assistant_message.assistant?
  end
end

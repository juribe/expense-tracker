# frozen_string_literal: true

require "test_helper"

class FinancialChatChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = User.create!(
      name: "Channel User",
      email: "chat_channel_test@example.com",
      password: "password123"
    )
  end

  test "subscribed streams on the user's dedicated stream name" do
    stub_connection(current_user: @user)
    subscribe
    assert_has_stream FinancialChatChannel.stream_name_for(@user)
  end
end

class FinancialChatBroadcastTest < ActionCable::TestCase
  setup do
    @user = User.create!(
      name: "Broadcast User",
      email: "chat_broadcast_test@example.com",
      password: "password123"
    )
  end

  test "broadcast delivers events to the user's stream" do
    FinancialChatChannel.broadcast(@user, event: "message_received", message: { role: "user" })
    assert_broadcast_on(FinancialChatChannel.stream_name_for(@user),
                        event: "message_received", message: { role: "user" })
  end
end

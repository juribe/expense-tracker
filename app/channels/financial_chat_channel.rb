# Streams the user's financial chat events (message acks, assistant
# processing/streaming/completed/failed notifications) in real time.
#
#   FinancialChatChannel.broadcast(user, event: "assistant_delta", delta: "...")
#
# Send flow lives in FinancialChat::MessagesController (HTTP POST); this
# channel is the read side.
class FinancialChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from self.class.stream_name_for(current_user)
  end

  class << self
    # Per-user stream name: the financial chat is one conversation per user.
    def stream_name_for(user)
      "financial_chat_user_#{user.id}"
    end

    def broadcast(user, event)
      ActionCable.server.broadcast(stream_name_for(user), event)
    end
  end
end

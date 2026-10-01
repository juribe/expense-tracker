# Analyzes a financial chat message asynchronously (Solid Queue).
#
# Started by FinancialChat::MessagesController after the user message is
# persisted; streams the assistant response through FinancialChatChannel.
class FinancialChatJob < ApplicationJob
  queue_as :ai

  def perform(chat_id, message_id)
    FinancialAnalysisService.new(chat_id: chat_id, message_id: message_id).call
  end
end

module FinancialChats
  class MessagesController < ApplicationController
    before_action :authenticate_user!

    def create
      chat = FinancialChat.for_user(current_user)
      message = chat.messages.new(role: "user", content: content)

      if content.blank? || !message.valid?
        return render json: { error: "Message content cannot be blank" }, status: :unprocessable_entity
      end

      message.update!(status: "sent")
      FinancialChatChannel.broadcast(current_user, event: "message_received", message: message.client_payload)
      FinancialChatJob.perform_later(chat.id, message.id)

      render json: { message: message.client_payload }, status: :created
    end

    private

    def content
      @content ||= params[:content].to_s.strip
    end
  end
end

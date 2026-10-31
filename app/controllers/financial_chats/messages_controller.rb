module FinancialChats
  class MessagesController < ApplicationController
    before_action :authenticate_user!

    # Every AI message costs money: a per-user ceiling for the assistant.
    # The limit counts per IP; per-user identity would leak message identity
    # into the rate-limit key, so keep it coarse.
    rate_limit to: 20, within: 1.minute, only: :create, store: RateLimitProxy.new

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

    # Removes the whole conversation so the user can start over. Scoped
    # through the current user's chat: no other conversation is reachable.
    def destroy
      current_user.financial_chat&.messages&.destroy_all

      redirect_to financial_chat_path, notice: t("financial_chat.cleared"), status: :see_other
    end

    private

    def content
      @content ||= params[:content].to_s.strip
    end
  end
end

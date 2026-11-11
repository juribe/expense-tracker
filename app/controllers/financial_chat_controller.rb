# frozen_string_literal: true

class FinancialChatController < ApplicationController
  require_premium

  before_action :authenticate_user!

  def show
    @chat = FinancialChat.for_user(current_user)
    @messages = @chat.messages.order(:created_at, :id).select { |message| message.user? || message.complete? }
  end
end

# One persistent financial-analysis conversation per user.
#
#   chat = FinancialChat.for_user(user)   # finds or creates the user's chat
#   chat.conversation_history             # role/content pairs for the LLM
class FinancialChat < ApplicationRecord
  ROLES = %w[user assistant].freeze
  STATUSES = %w[sent processing streaming complete failed].freeze

  belongs_to :user
  has_many :messages, -> { order(:created_at, :id) },
           class_name: "FinancialChatMessage", dependent: :destroy

  validates :user, presence: true
  validates :user_id, uniqueness: true

  # The user has exactly one conversation; create it on first access.
  def self.for_user(user)
    find_or_create_by!(user: user)
  end

  # Role/content pairs for the LLM; oldest-first, already chronologically
  # ordered through the messages association.
  def conversation_history
    messages.merge(FinancialChatMessage.complete).map { |message| { role: message.role, content: message.content } }
  end
end

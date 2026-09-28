# frozen_string_literal: true

# WhatsappConnection
# The current active link between a user and a WhatsApp identity. A number can
# have at most one active connection (enforced by validation and a partial
# unique DB index). Disconnecting timestamps the row without deleting it: the
# user's expenses and the identity claim both survive untouched.
#
# Associations: belongs_to :user, belongs_to :whatsapp_identity.
#
# Example: connection.disconnect!
class WhatsappConnection < ApplicationRecord
  belongs_to :user
  belongs_to :whatsapp_identity

  scope :active, -> { where(disconnected_at: nil) }

  # At most one active connection per identity; disconnected rows don't count.
  validates :whatsapp_identity_id,
            uniqueness: { conditions: -> { where(disconnected_at: nil) } }

  def active?
    disconnected_at.nil?
  end

  def disconnect!
    update!(disconnected_at: Time.current) if active?
    self
  end
end

# frozen_string_literal: true

# Whatsapp::ConnectService
# Handles the "CONNECT <code>" command received by the webhook. Proves number
# ownership (the command must come from the WhatsApp number itself), claims or
# reuses the permanent WhatsappIdentity, enforces the anti-abuse ownership
# rules and opens the active WhatsappConnection. The pending token is consumed
# atomically; the user is confirmed through WhatsApp.
#
# Rejection rules (generic messages, no other-account details are revealed):
#   * invalid / expired / already-used codes
#   * numbers already claimed by a different account (no ownership transfer)
#
# Example: Whatsapp::ConnectService.call(event: message_event)
module Whatsapp
  class ConnectService
    CONNECT_PATTERN = /\A\s*CONNECT\s+([A-Z0-9]{4,10})\z/i

    def self.call(event:)
      new(event: event).call
    end

    def initialize(event:)
      @event = event
    end

    def call
      return ServiceResult.error([ "Invalid CONNECT command." ]) unless (code = extract_code)

      pending = PendingWhatsappConnection.valid_pending_for(code)
      unless pending
        reject(sender, "Ese código no es válido o ya expiró. Genera uno nuevo en Configuración → WhatsApp del Expense Tracker.")
        return ServiceResult.error([ "Invalid, expired or already-used connect token." ])
      end

      identity = WhatsappIdentity.claim_for!(pending.user, sender)
      if identity.claimed_by_user_id != pending.user_id
        reject(sender, "Este número de WhatsApp no se puede conectar a esta cuenta.")
        return ServiceResult.error([ "WhatsApp number already claimed by another account." ])
      end

      connection = establish_connection!(pending.user, identity)
      pending.consume!
      Whatsapp::ReplySender.send_to(sender, "✅ WhatsApp conectado. Ya puedes enviarme tus gastos por este chat.")
      ServiceResult.success(connection)
    end

    private

    def sender
      @sender ||= WhatsappIdentity.normalize(@event.sender_id)
    end

    def extract_code
      text = @event.text.to_s
      CONNECT_PATTERN.match(text)&.captures&.first
    end

    def establish_connection!(user, identity)
      identity.whatsapp_connections.active.find_by(user: user) ||
        WhatsappConnection.create!(user: user, whatsapp_identity: identity, connected_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      identity.whatsapp_connections.active.first
    end

    def reject(phone_number, reply_text)
      Whatsapp::ReplySender.send_to(phone_number, reply_text)
      nil
    end
  end
end

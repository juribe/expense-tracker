# frozen_string_literal: true

# Whatsapp::ConnectService
# Handles the initial WhatsApp message ("Hola yogasto…") carrying a CONNECT
# token, plus the bare "CONNECT <code>" command. Proves number ownership (the
# token must arrive from the WhatsApp number itself), claims or reuses the
# permanent WhatsappIdentity, enforces the anti-abuse ownership rules and
# opens the active WhatsappConnection. The pending token is consumed
# atomically; the user is confirmed through WhatsApp.
#
# The greeting alone never identifies an account: without a valid single-use
# token nothing is linked.
#
# Rejection rules (generic messages, no other-account details are revealed):
#   * invalid / expired / already-used codes
#   * numbers already claimed by a different account (no ownership transfer)
#
# Example: Whatsapp::ConnectService.call(event: message_event)
module Whatsapp
  class ConnectService
    INITIAL_MESSAGE = "Hola yogasto quiero registrar mis gastos usando whatsapp"
    CONNECT_PATTERN =
      /\A\s*(?:#{Regexp.escape(INITIAL_MESSAGE)}\.?\s+)?CONNECT\s+([A-Z0-9]{4,10})\s*\z/i
    # Broad routing signal used by the webhook: malformed codes still reach
    # this service and get the generic rejection instead of being parsed as
    # an expense.
    CONNECT_INTENT_PATTERN =
      /\A\s*(?:#{Regexp.escape(INITIAL_MESSAGE)}\.?\s+)?CONNECT\s+\S+/i

    def self.call(event:)
      new(event: event).call
    end

    def self.connect_command?(text)
      CONNECT_INTENT_PATTERN.match?(text.to_s)
    end

    def initialize(event:)
      @event = event
    end

    def call
      return ServiceResult.error([ "Invalid CONNECT command." ]) unless (code = extract_code)

      pending = PendingWhatsappConnection.valid_pending_for(code)
      unless pending
        reject(sender, "Ese código no es válido o ya expiró. Genera uno nuevo en Configuración → WhatsApp de #{AppName.current}.")
        return ServiceResult.error([ "Invalid, expired or already-used connect token." ])
      end

      connection = ActiveRecord::Base.transaction do
        PremiumIdentities::Protection.claim!(
          identity_type: "whatsapp",
          value: sender,
          user: pending.user,
          membership: PaymentEngine::UserAccess.new(pending.user.id).current_membership
        )
        identity = WhatsappIdentity.claim_for!(pending.user, sender)
        unless identity.claimed_by_user_id == pending.user_id
          raise PremiumIdentities::Protection::Conflict, "WhatsApp number already claimed by another account."
        end

        establish_connection!(pending.user, identity)
      end
      pending.consume!
      Whatsapp::ReplySender.send_to(sender, "✅ WhatsApp conectado. Ya puedes enviarme tus gastos por este chat.")
      ServiceResult.success(connection)
    rescue PremiumIdentities::Protection::Conflict => e
      reject(sender, "Este número de WhatsApp no se puede conectar a esta cuenta.")
      ServiceResult.error([ e.message ])
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

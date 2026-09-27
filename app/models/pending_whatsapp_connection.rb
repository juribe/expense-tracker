# frozen_string_literal: true

# PendingWhatsappConnection
# Short-lived, single-use connect tokens shown in Settings → WhatsApp. The
# user sends "CONNECT <code>" from the WhatsApp number being linked; only a
# SHA-256 digest of the code is stored, so a DB leak never exposes usable
# tokens. Codes use an unambiguous alphabet (no I/L/O/0/1) so they can be
# safely copied by hand from the instructions page.
#
# Associations: belongs_to :user.
#
# Example: code = PendingWhatsappConnection.generate_for!(user)
class PendingWhatsappConnection < ApplicationRecord
  TOKEN_TTL = 10.minutes
  CODE_LENGTH = 5
  # 30 unambiguous characters: no I, L, O, 0, 1.
  ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".freeze

  belongs_to :user

  scope :unused, -> { where(used_at: nil) }
  scope :unexpired, -> { where("expires_at > ?", Time.current) }

  validates :token_digest, :expires_at, presence: true

  # Returns the raw code (for the UI) and persists only its digest.
  def self.generate_for!(user, ttl: TOKEN_TTL)
    code = CODE_LENGTH.times.map { ALPHABET.chars.sample }.join
    user.pending_whatsapp_connections.create!(token_digest: digest_of(code), expires_at: ttl.from_now)
    code
  end

  def self.digest_of(code)
    Digest::SHA256.hexdigest(code.to_s.upcase.strip)
  end

  # Fresh = unused and unexpired. Case-insensitive because users type the code
  # on a phone keyboard.
  def self.valid_pending_for(code)
    where(token_digest: digest_of(code)).unused.where("expires_at > ?", Time.current).first
  end

  # Atomic single-use consumption: returns true only for the first caller.
  def consume!
    self.class.where(id: id, used_at: nil).update_all(used_at: Time.current) == 1
  end
end

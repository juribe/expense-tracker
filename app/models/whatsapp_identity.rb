# frozen_string_literal: true

# WhatsappIdentity
# Permanent, historical claim of a WhatsApp phone number by the first Expense
# Tracker account that connected it. This row is never deleted by a
# disconnect: the number stays bound to the claiming account forever, which is
# the anti-abuse signal that stops users from re-claiming the same number with
# new accounts to obtain fresh trials.
#
# Associations: belongs_to :claimed_by_user (optional; survives user churn),
# has_many :whatsapp_connections (at most one active at a time).
#
# Example: WhatsappIdentity.claim_for!(user, "+57 300 123 4567")
class WhatsappIdentity < ApplicationRecord
  E164_FORMAT = /\A\+[1-9]\d{7,14}\z/

  encrypts :phone_number, deterministic: true

  belongs_to :claimed_by_user, class_name: "User", optional: true
  has_many :whatsapp_connections

  validates :phone_number, presence: true, uniqueness: true, format: { with: E164_FORMAT }

  before_validation { self.phone_number = self.class.normalize(phone_number) }

  # E.164 normalization so "+57 300 123 4567", "573001234567" and local
  # international prefixes resolve to the same real-world WhatsApp number.
  def self.normalize(phone_number)
    digits = phone_number.to_s.gsub(/\D/, "")
    return "" if digits.blank?

    digits = digits.delete_prefix("00") if digits.start_with?("00")
    "+#{digits}"
  end

  # WhatsApp's wa_id is digits-only, even though the stored number is E.164.
  def self.wa_id(phone_number)
    phone_number.to_s.gsub(/\D/, "")
  end

  # Claims the number for +user+ on first use; if it was already claimed (even
  # by a different account, or in a race), returns the existing identity
  # untouched. Ownership checks happen at the service layer.
  def self.claim_for!(user, phone_number)
    normalized = normalize(phone_number)
    find_by(phone_number: normalized) ||
      create!(phone_number: normalized, claimed_by_user: user, claimed_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    find_by!(phone_number: normalized)
  end

  def active_connection
    whatsapp_connections.active.first
  end
end

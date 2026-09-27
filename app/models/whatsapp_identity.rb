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
  belongs_to :claimed_by_user, class_name: "User", optional: true
  has_many :whatsapp_connections

  validates :phone_number, presence: true, uniqueness: true

  before_validation { self.phone_number = self.class.normalize(phone_number) }

  # Digits-only normalization so "+57 300 123 4567" and "573001234567" are the
  # same real-world WhatsApp number.
  def self.normalize(phone_number)
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

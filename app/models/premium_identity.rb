# frozen_string_literal: true

# PremiumIdentity
# Permanent fingerprint of an identifier used to access premium features.
#
# Associations: belongs_to :first_user (optional; survives user deletion),
# belongs_to :membership (optional), belongs_to :released_by_user (optional).
# Methods: released?, owned_by?, available_to?
#
# Example: PremiumIdentity.find_by(fingerprint: PremiumIdentities::Fingerprint.call(...))
class PremiumIdentity < ApplicationRecord
  IDENTITY_TYPES = %w[account_email whatsapp gmail redirect_email].freeze

  belongs_to :first_user, class_name: "User", optional: true, inverse_of: :premium_identities
  belongs_to :membership, class_name: "PaymentEngine::Membership",
                          foreign_key: :payment_engine_membership_id, optional: true
  belongs_to :released_by_user, class_name: "User", optional: true

  validates :identity_type, inclusion: { in: IDENTITY_TYPES }
  validates :fingerprint, presence: true, uniqueness: true,
                          format: { with: /\A[0-9a-f]{64}\z/ }
  validates :first_used_at, presence: true

  scope :active, -> { where(released_at: nil) }
  scope :released, -> { where.not(released_at: nil) }

  def released?
    released_at.present?
  end

  def owned_by?(user)
    user.present? && first_user_id == user.id
  end

  def available_to?(user)
    released? || owned_by?(user)
  end
end

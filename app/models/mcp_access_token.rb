# frozen_string_literal: true

# McpAccessToken
# User-scoped credential for external MCP clients. Only the SHA-256 digest is
# persisted; the readable token is returned once by .issue!.
#
# Associations: belongs_to :user
# Methods: issue!, authenticate, digest, allows?, revoke!, revoked?, expired?,
#   active?, touch_last_used!
#
# Example: token, plain = McpAccessToken.issue!(user: user, name: "Claude",
#   scopes: [ :read ])
class McpAccessToken < ApplicationRecord
  SCOPES = %w[read write].freeze
  LAST_USED_THROTTLE = 1.minute

  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validate :scopes_are_known

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.issue!(user:, name:, scopes: [ "read" ], expires_at: nil)
    plain = "ygm_#{SecureRandom.urlsafe_base64(32)}"
    token = create!(
      user: user,
      name: name,
      token_digest: digest(plain),
      scopes: Array(scopes).map(&:to_s),
      expires_at: expires_at
    )
    [ token, plain ]
  end

  def self.authenticate(plain)
    return nil if plain.blank?

    token = find_by(token_digest: digest(plain))
    token if token&.active?
  end

  def self.digest(plain)
    Digest::SHA256.hexdigest(plain.to_s)
  end

  def allows?(scope)
    active? && scopes.include?(scope.to_s)
  end

  def active?
    !revoked? && !expired?
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  # Avoids a write on every tool call while still keeping an audit-friendly
  # last usage timestamp.
  def touch_last_used!
    return if last_used_at.present? && last_used_at > LAST_USED_THROTTLE.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def scopes_are_known
    known = Array(scopes)
    errors.add(:scopes, "must include read") unless known.include?("read")

    unknown = known - SCOPES
    errors.add(:scopes, "contain unknown scopes: #{unknown.join(', ')}") if unknown.any?
  end
end

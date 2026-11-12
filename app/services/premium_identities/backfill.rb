# frozen_string_literal: true

# PremiumIdentities::Backfill
# One-time, idempotent import of premium identities that already exist as
# memberships, Gmail connections, redirect email sources or WhatsApp claims.
# Conflicts are counted instead of aborting the whole run.
#
# Example: PremiumIdentities::Backfill.call
module PremiumIdentities
  class Backfill
    class << self
      def call
        new.call
      end
    end

    def initialize
      @counts = { claimed: 0, conflicts: 0, conflict_details: [] }
    end

    def call
      backfill_memberships
      backfill_gmail_connections
      backfill_redirect_emails
      backfill_whatsapp_identities
      @counts
    end

    private

    def backfill_memberships
      PaymentEngine::Membership.where(owner_type: "User").includes(:owner).find_each do |membership|
        owner = membership.owner
        next unless owner.is_a?(User)

        claim(identity_type: "account_email", value: owner.email, user: owner, membership: membership)
      end
    end

    def backfill_gmail_connections
      GmailConnection.includes(:user).find_each do |connection|
        claim(
          identity_type: "gmail",
          value: connection.email,
          user: connection.user,
          membership: current_membership_for(connection.user)
        )
      end
    end

    def backfill_redirect_emails
      EmailSource.where.not(email: [ nil, "" ]).includes(:user).find_each do |source|
        claim(
          identity_type: "redirect_email",
          value: source.email,
          user: source.user,
          membership: current_membership_for(source.user)
        )
      end
    end

    def backfill_whatsapp_identities
      WhatsappIdentity.includes(:claimed_by_user).find_each do |identity|
        user = identity.claimed_by_user
        next unless user

        claim(
          identity_type: "whatsapp",
          value: identity.phone_number,
          user: user,
          membership: current_membership_for(user)
        )
      end
    end

    def claim(identity_type:, value:, user:, membership:)
      return if value.blank?

      PremiumIdentities::Protection.claim!(
        identity_type: identity_type,
        value: value,
        user: user,
        membership: membership
      )
      @counts[:claimed] += 1
    rescue PremiumIdentities::Protection::Conflict => e
      @counts[:conflicts] += 1
      @counts[:conflict_details] << {
        identity_type: identity_type,
        user_id: user&.id,
        membership_id: membership&.id,
        error: e.message
      }
      Rails.logger.warn("Premium identity backfill conflict for #{identity_type} (user #{user&.id})")
    end

    def current_membership_for(user)
      return nil unless user

      PaymentEngine::Membership.where(owner: user).order(expires_at: :desc).first
    end
  end
end

# frozen_string_literal: true

# PremiumIdentities::Capture
# Records every premium identity a user owns. Used before account deletion so
# memberships created before the protection existed still keep their identity
# history. Conflicting identities are logged instead of blocking the deletion.
#
# Example: PremiumIdentities::Capture.call(user)
module PremiumIdentities
  class Capture
    class << self
      def call(user)
        new(user: user).call
      end
    end

    def initialize(user:)
      @user = user
      @counts = Hash.new(0)
    end

    def call
      membership = current_membership
      return @counts unless membership

      claim("account_email", @user.email, membership)
      @user.gmail_connections.find_each { |connection| claim("gmail", connection.email, membership) }
      @user.email_sources.where.not(email: [ nil, "" ])
           .find_each { |source| claim("redirect_email", source.email, membership) }
      @user.whatsapp_identities.find_each { |identity| claim("whatsapp", identity.phone_number, membership) }
      @counts
    end

    private

    def current_membership
      PaymentEngine::Membership.where(owner: @user).order(expires_at: :desc).first
    end

    def claim(identity_type, value, membership)
      return if value.blank?

      PremiumIdentities::Protection.claim!(
        identity_type: identity_type,
        value: value,
        user: @user,
        membership: membership
      )
      @counts[:claimed] += 1
    rescue PremiumIdentities::Protection::Conflict
      @counts[:conflicts] += 1
      Rails.logger.warn("Premium identity capture conflict for #{identity_type} (user #{@user.id})")
    end
  end
end

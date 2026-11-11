# frozen_string_literal: true

# Whatsapp::PremiumMembershipGate
# Blocks WhatsApp expense capture for users without an active premium
# membership and sends them a single notice per membership version per day.
#
# The notice is throttled through Solid Cache. The key is scoped to the user
# and the current membership's updated_at, so renewing or modifying the
# membership generates a new key and re-enables WhatsApp immediately.
#
# Example: Whatsapp::PremiumMembershipGate.blocks?(user: user, phone_number: phone)
module Whatsapp
  class PremiumMembershipGate
    CACHE_KEY_PREFIX = "premium_expired_notice"
    NO_MEMBERSHIP_VERSION = "none"

    def self.blocks?(user:, phone_number:)
      new(user: user, phone_number: phone_number).blocks?
    end

    def initialize(user:, phone_number:)
      @user = user
      @phone_number = phone_number
    end

    def blocks?
      return false if PaymentEngine::AccessPolicy.premium_access?(user)

      notify_once
      true
    end

    private

    attr_reader :user, :phone_number

    def notify_once
      return unless claim_notice

      delivered = Whatsapp::ReplySender.send_to(phone_number, notice_text)
      Rails.cache.delete(notice_cache_key) unless delivered
    end

    # A successful write means this message owns the single daily notice.
    # The user row lock serializes concurrent messages for the same user;
    # Solid Cache's unless_exist alone does not lock a key that does not exist.
    def claim_notice
      claimed = false
      user.with_lock do
        claimed = Rails.cache.write(notice_cache_key, true, expires_in: seconds_until_midnight, unless_exist: true)
      end
      claimed
    end

    def notice_cache_key
      "#{CACHE_KEY_PREFIX}:#{user.id}:#{membership_version}"
    end

    def membership_version
      membership = PaymentEngine::UserAccess.new(user.id).current_membership
      membership ? membership.updated_at.utc.iso8601(6) : NO_MEMBERSHIP_VERSION
    end

    def seconds_until_midnight
      (Time.current.tomorrow.beginning_of_day - Time.current).to_i
    end

    def notice_text
      I18n.t("whatsapp.premium_membership.expired_notice", app_name: AppName.current)
    end
  end
end

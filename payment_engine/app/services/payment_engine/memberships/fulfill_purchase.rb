# frozen_string_literal: true

module PaymentEngine
  module Memberships
    # Grants or extends membership access for a paid purchase.
    #
    # A purchase made while the owner still has an active membership is treated as
    # an early renewal: the purchased duration is added to the current expiration
    # date instead of starting over from the payment date.
    class FulfillPurchase
      def self.call(purchase:)
        new(purchase: purchase).call
      end

      def initialize(purchase:)
        @purchase = purchase
      end

      def call
        purchase.with_lock do
          purchase.reload
          next success(purchase.membership) if purchase.membership

          option = purchase.payment_option
          next success(nil) if option.nil?

          existing = active_membership_for(option)
          result = early_renewal?(existing) ? extend(existing, option) : grant(option)

          next result unless result.success?

          purchase.update!(membership_id: result.record.id)
          result
        end
      rescue StandardError => error
        PaymentEngine::Result.new(success: false, errors: [error.message])
      end

      private

      attr_reader :purchase

      def active_membership_for(option)
        Membership
          .where(owner: purchase.owner, membership_type: option.membership_type, status: "active")
          .order(expires_at: :desc)
          .first
      end

      def early_renewal?(membership)
        membership&.expires_at.present? && membership.expires_at > Time.current
      end

      def extend(membership, option)
        # Lock the row and re-read it so concurrent renewals accumulate instead
        # of overwriting each other.
        membership.lock!

        return grant(option) unless early_renewal?(membership)

        Extend.call(
          membership: membership,
          duration: option.access_duration,
          reason: "renewal"
        )
      end

      def grant(option)
        starts_at = purchase.created_at || Time.current
        Grant.call(
          owner: purchase.owner,
          membership_type: option.membership_type,
          starts_at: starts_at,
          expires_at: starts_at + option.access_duration,
          source: "purchase",
          purchase: purchase
        )
      end

      def success(record)
        PaymentEngine::Result.new(success: true, record: record)
      end
    end
  end
end

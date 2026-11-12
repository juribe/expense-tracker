# frozen_string_literal: true

module PaymentEngine
  module Memberships
    # Revokes the access granted by a refunded purchase.
    #
    # Honours the engine's revoke_access_on_refund setting. A purchase without
    # a membership, or one whose membership is already inactive, is a no-op.
    #
    # Example: PaymentEngine::Memberships::RevokeForRefund.call(purchase: purchase)
    class RevokeForRefund
      def self.call(purchase:, actor: nil, reason: nil)
        new(purchase: purchase, actor: actor, reason: reason).call
      end

      def initialize(purchase:, actor: nil, reason: nil)
        @purchase = purchase
        @actor = actor
        @reason = reason
      end

      def call
        return success unless PaymentEngine.configuration.revoke_access_on_refund

        membership = purchase.membership || Membership.find_by(purchase: purchase)
        return success if membership.nil? || !membership.active?

        Cancel.call(membership: membership, actor: actor, reason: reason)
      end

      private

      attr_reader :purchase, :actor, :reason

      def success
        PaymentEngine::Result.new(success: true)
      end
    end
  end
end

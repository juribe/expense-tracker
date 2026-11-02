module PaymentEngine
  module Memberships
    # Starts an authorized free trial. A trial is a membership in trialing
    # status; it is not a subscription and does not charge the owner.
    class StartTrial
      def self.call(owner:, payment_option:, starts_at: nil)
        new(owner: owner, payment_option: payment_option, starts_at: starts_at).call
      end

      def initialize(owner:, payment_option:, starts_at: nil)
        @owner = owner
        @payment_option = payment_option
        @starts_at = starts_at
      end

      def call
        return Result.failure(code: :invalid_option, errors: [ "trial is not available for this option" ]) unless eligible?

        Grant.call(
          owner: owner,
          membership_type: payment_option.membership_type,
          payment_option: payment_option,
          duration: Duration.new(interval: "day", count: payment_option.trial_days),
          starts_at: starts_at,
          status: "trialing",
          metadata: { "source" => "trial" }
        )
      end

      private

      attr_reader :owner, :payment_option, :starts_at

      def eligible?
        payment_option.present? &&
          payment_option.active? &&
          payment_option.membership_type.active? &&
          payment_option.trial_days.to_i.positive?
      end
    end
  end
end

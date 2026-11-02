module PaymentEngine
  module Payments
    # Confirms an approved payment and activates or extends the membership.
    #
    # Idempotent by design:
    # - an already approved payment returns success without side effects;
    # - a completed purchase is never extended again by a second payment;
    # - the provider transaction id is unique per provider at database level.
    class Confirm
      def self.call(payment:, provider_transaction_id: nil, paid_at: nil, amount: nil,
                    currency: nil, payment_method: nil, metadata: {})
        new(
          payment: payment,
          provider_transaction_id: provider_transaction_id,
          paid_at: paid_at,
          amount: amount,
          currency: currency,
          payment_method: payment_method,
          metadata: metadata
        ).call
      end

      def initialize(payment:, provider_transaction_id: nil, paid_at: nil, amount: nil,
                     currency: nil, payment_method: nil, metadata: {})
        @payment = payment
        @provider_transaction_id = provider_transaction_id
        @paid_at = paid_at
        @amount = amount
        @currency = currency
        @payment_method = payment_method
        @metadata = metadata.to_h
      end

      def call
        return failure(:not_found, "payment not found") if payment.blank?

        outcome = nil
        granted_membership = nil

        Payment.transaction do
          payment.lock!

          if payment.approved?
            outcome = Result.success(data: payment, code: :already_approved)
            next
          end

          unless %w[pending processing].include?(payment.status)
            outcome = failure(:invalid_state, "payment cannot be approved from #{payment.status}")
            next
          end

          if mismatch?
            payment.update!(failure_reason: mismatch_message)
            outcome = failure(:amount_mismatch, mismatch_message)
            next
          end

          if duplicate_transaction?
            outcome = failure(:duplicate_transaction, "this provider transaction was already recorded")
            next
          end

          approve_payment!
          purchase = payment.purchase
          purchase.lock!

          if purchase.completed?
            outcome = Result.success(data: payment, code: :already_completed)
            next
          end

          grant_result = grant_membership(purchase)
          unless grant_result.success?
            outcome = grant_result
            raise ActiveRecord::Rollback
          end

          granted_membership = grant_result.data
          purchase.update!(status: "completed", purchased_at: paid_at || PaymentEngine.current_time,
                           membership: granted_membership)
          payment.update!(membership: granted_membership)
          outcome = Result.success(data: payment, code: :approved)
        end

        return outcome if outcome.nil? || outcome.error?

        publish_events(outcome.code)
        outcome
      rescue ActiveRecord::RecordNotUnique => error
        Result.failure(code: :duplicate_transaction, errors: [ error.message ])
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_record, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :payment, :provider_transaction_id, :paid_at, :amount, :currency,
                  :payment_method, :metadata

      def mismatch?
        amount_mismatch? || currency_mismatch?
      end

      def amount_mismatch?
        amount.present? && amount.to_i != payment.amount.to_i
      end

      def currency_mismatch?
        currency.present? && currency.to_s.upcase != payment.currency.to_s.upcase
      end

      def mismatch_message
        return "payment amount does not match the purchase" if amount_mismatch?

        "payment currency does not match the purchase"
      end

      def duplicate_transaction?
        return false if provider_transaction_id.blank?

        Payment.where(provider: payment.provider, provider_transaction_id: provider_transaction_id)
          .where.not(id: payment.id)
          .exists?
      end

      def approve_payment!
        payment.assign_attributes(
          status: "approved",
          paid_at: paid_at || PaymentEngine.current_time,
          provider_transaction_id: provider_transaction_id.presence || payment.provider_transaction_id,
          payment_method: payment_method.presence || payment.payment_method,
          failure_reason: nil,
          metadata: payment.metadata.merge(metadata)
        )
        payment.save!
      end

      def grant_membership(purchase)
        option = purchase.payment_option
        Memberships::Grant.call(
          owner: purchase.owner,
          membership_type: option.membership_type,
          payment_option: option,
          duration: purchase.duration_object,
          membership: purchase.membership || payment.membership,
          metadata: { "purchase_id" => purchase.id }
        )
      end

      def publish_events(code)
        return if code == :already_approved

        Events.publish_after_commit(:payment_approved, payment: payment, purchase: payment.purchase)
      end

      def failure(code, message)
        Result.failure(code: code, errors: [ message ])
      end
    end
  end
end

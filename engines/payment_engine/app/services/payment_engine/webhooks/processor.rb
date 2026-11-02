module PaymentEngine
  module Webhooks
    # Dispatches a normalized provider event to the domain services. The event is
    # only marked processed after the business operation succeeds; failures keep
    # the error and can be retried.
    class Processor
      def self.call(event)
        new(event).call
      end

      def initialize(event)
        @event = event
      end

      def call
        return event if event.processed? || event.ignored?

        already_done = false
        event.with_lock do
          if event.processed? || event.ignored?
            already_done = true
          else
            event.mark_processing!
          end
        end
        return event if already_done

        dispatch
        return event if event.ignored?

        event.mark_processed!
        event
      rescue StandardError => error
        event.mark_failed!(error)
        raise
      end

      private

      attr_reader :event

      def dispatch
        data = normalized_data
        handler = HANDLERS[event.event_type]

        unless handler
          event.mark_ignored!("Unhandled event type: #{event.event_type}")
          return
        end

        send(handler, data)
      end

      HANDLERS = {
        "payment.approved" => :handle_payment_approved,
        "payment.rejected" => :handle_payment_rejected,
        "payment.refunded" => :handle_payment_refunded,
        "subscription.created" => :handle_subscription_created,
        "subscription.renewed" => :handle_subscription_renewed,
        "subscription.canceled" => :handle_subscription_canceled,
        "subscription.payment_failed" => :handle_subscription_payment_failed
      }.freeze

      def normalized_data
        raw = event.payload["_payment_engine"] || event.payload[:_payment_engine] || {}
        raw.to_h.symbolize_keys
      end

      def handle_payment_approved(data)
        payment = find_payment(data)
        raise ProcessingError, "payment not found for approved event" if payment.blank?

        ensure_success!(
          Payments::Confirm.call(
            payment: payment,
            provider_transaction_id: data[:provider_transaction_id],
            amount: data[:amount],
            currency: data[:currency],
            paid_at: data[:paid_at],
            payment_method: data[:payment_method],
            metadata: data[:metadata].to_h
          )
        )
      end

      def handle_payment_rejected(data)
        payment = find_payment(data)
        raise ProcessingError, "payment not found for rejected event" if payment.blank?

        ensure_success!(
          Payments::Reject.call(
            payment: payment,
            failure_reason: data[:failure_reason],
            provider_transaction_id: data[:provider_transaction_id],
            metadata: data[:metadata].to_h
          )
        )
      end

      def handle_payment_refunded(data)
        payment = find_payment(data)
        raise ProcessingError, "payment not found for refunded event" if payment.blank?

        ensure_success!(
          Payments::Refund.call(
            payment: payment,
            amount: data[:amount],
            reason: data[:failure_reason] || data[:reason],
            metadata: data[:metadata].to_h
          )
        )
      end

      def handle_subscription_created(data)
        subscription = find_subscription(data)
        if subscription
          ensure_success!(sync_subscription(subscription, data))
          return
        end

        membership = find_membership(data)
        raise ProcessingError, "membership not found for subscription event" if membership.blank?

        ensure_success!(
          Subscriptions::Create.call(
            membership: membership,
            payment_option: membership.payment_option,
            provider: event.provider,
            provider_subscription_id: data[:provider_subscription_id],
            status: data[:status].presence || "active",
            starts_at: data[:period_starts_at],
            ends_at: data[:period_ends_at],
            next_billing_at: data[:next_billing_at],
            trial_ends_at: data[:trial_ends_at],
            metadata: data[:metadata].to_h
          )
        )
      end

      def handle_subscription_renewed(data)
        subscription = find_subscription(data)
        raise ProcessingError, "subscription not found for renewal event" if subscription.blank?

        ensure_success!(
          Subscriptions::RecordRenewal.call(
            subscription: subscription,
            provider_transaction_id: data[:provider_transaction_id] || event.event_id,
            amount: data[:amount],
            currency: data[:currency],
            paid_at: data[:paid_at],
            period_starts_at: data[:period_starts_at],
            period_ends_at: data[:period_ends_at],
            metadata: data[:metadata].to_h
          )
        )
      end

      def handle_subscription_canceled(data)
        subscription = find_subscription(data)
        raise ProcessingError, "subscription not found for cancellation event" if subscription.blank?

        ensure_success!(
          Subscriptions::ApplyProviderCancellation.call(
            subscription: subscription,
            immediately: data[:immediately] == true
          )
        )
      end

      def handle_subscription_payment_failed(data)
        subscription = find_subscription(data)
        raise ProcessingError, "subscription not found for failed payment event" if subscription.blank?

        ensure_success!(
          Subscriptions::RecordPaymentFailure.call(
            subscription: subscription,
            failure_reason: data[:failure_reason],
            provider_transaction_id: data[:provider_transaction_id],
            amount: data[:amount],
            currency: data[:currency],
            paid_at: data[:paid_at],
            metadata: data[:metadata].to_h
          )
        )
      end

      def find_payment(data)
        if data[:payment_id].present?
          return Payment.find_by(id: data[:payment_id]) || raise(ProcessingError, "payment not found")
        end

        payment = Payment.find_by(provider: event.provider, provider_transaction_id: data[:provider_transaction_id]) if data[:provider_transaction_id].present?
        return payment if payment

        return if data[:purchase_id].blank?

        purchase = Purchase.find_by(id: data[:purchase_id])
        raise ProcessingError, "purchase not found" if purchase.blank?

        purchase.payments.where(provider: event.provider).order(:id).last ||
          purchase.payments.create!(provider: event.provider, amount: purchase.amount,
                                    currency: purchase.currency, status: "pending")
      end

      def find_subscription(data)
        if data[:subscription_id].present?
          return Subscription.find_by(id: data[:subscription_id]) || raise(ProcessingError, "subscription not found")
        end

        return if data[:provider_subscription_id].blank?

        Subscription.find_by(provider: event.provider, provider_subscription_id: data[:provider_subscription_id])
      end

      def find_membership(data)
        return Membership.find_by(id: data[:membership_id]) if data[:membership_id].present?
        return if data[:purchase_id].blank?

        Purchase.find_by(id: data[:purchase_id])&.membership
      end

      def sync_subscription(subscription, data)
        subscription.with_lock do
          subscription.update!(
            status: data[:status].presence || subscription.status,
            current_period_starts_at: data[:period_starts_at] || subscription.current_period_starts_at,
            current_period_ends_at: data[:period_ends_at] || subscription.current_period_ends_at,
            next_billing_at: data[:next_billing_at] || subscription.next_billing_at
          )
        end

        Result.success(data: subscription)
      end

      def ensure_success!(result)
        return result if result.success?

        raise ProcessingError, result.error_message
      end
    end
  end
end

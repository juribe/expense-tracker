module PaymentEngine
  module Providers
    class Fake < Base
      def self.capabilities
        %i[customers payments refunds tokenization recurring_payments subscription_cancellation webhooks]
      end

      def create_customer(owner:, email: nil, metadata: {})
        PaymentEngine::Result.success(
          data: { provider_customer_id: "fake-customer-#{owner.class.name}-#{owner.id}" }
        )
      end

      def create_payment(purchase:, payment:, customer: nil, return_url: nil, confirmation_url: nil)
        PaymentEngine::Result.success(
          data: {
            checkout: { url: "https://fake.payment.test/checkout/#{purchase.id}" },
            provider_transaction_id: "fake-#{purchase.id}-#{SecureRandom.hex(6)}"
          }
        )
      end

      def fetch_payment(provider_transaction_id:)
        PaymentEngine::Result.success(data: { provider_transaction_id: provider_transaction_id, status: "approved" })
      end

      def create_subscription(subscription:, customer: nil, payment_method_token: nil)
        PaymentEngine::Result.success(data: { provider_subscription_id: "fake-sub-#{SecureRandom.hex(6)}" })
      end

      def cancel_subscription(provider_subscription_id:, immediately: false)
        PaymentEngine::Result.success(data: { provider_subscription_id: provider_subscription_id, status: "canceled" })
      end

      def fetch_subscription(provider_subscription_id:)
        PaymentEngine::Result.success(data: { provider_subscription_id: provider_subscription_id, status: "active" })
      end

      def refund_payment(provider_transaction_id:, amount: nil, reason: nil)
        PaymentEngine::Result.success(data: { provider_transaction_id: provider_transaction_id, status: "refunded" })
      end

      def verify_webhook(payload:, headers: {}, raw_body: nil)
        expected = settings[:webhook_secret].to_s
        return false if expected.empty?

        provided = header_value(headers, "X-Fake-Signature").to_s
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def parse_webhook(payload:, headers: {}, raw_body: nil)
        data = payload.to_h.symbolize_keys rescue {}
        normalized = data[:data].to_h.symbolize_keys rescue {}
        PaymentEngine::Result.success(
          data: normalized.merge(
            event_id: data[:event_id] || normalized[:event_id],
            event_type: data[:event_type] || normalized[:event_type]
          )
        )
      end
    end
  end
end
module PaymentEngine
  module Providers
    # Common contract for payment provider adapters. Every operation returns a
    # PaymentEngine::Result. Unsupported operations return a controlled error
    # instead of simulating capabilities the provider does not have.
    class Base
      class << self
        def capabilities
          []
        end

        def provider_name
          name.to_s.split("::").last.underscore.to_sym
        end
      end

      attr_reader :settings

      def initialize(settings: {})
        @settings = settings.to_h.symbolize_keys
      end

      def name
        self.class.provider_name
      end

      def supports?(capability)
        self.class.capabilities.map(&:to_sym).include?(capability.to_sym)
      end

      def create_customer(owner:, email: nil, metadata: {})
        unsupported(:create_customer)
      end

      def create_payment(purchase:, payment:, customer: nil, return_url: nil, confirmation_url: nil)
        unsupported(:create_payment)
      end

      def fetch_payment(provider_transaction_id:)
        unsupported(:fetch_payment)
      end

      def create_subscription(subscription:, customer: nil, payment_method_token: nil)
        unsupported(:create_subscription)
      end

      def cancel_subscription(provider_subscription_id:, immediately: false)
        unsupported(:cancel_subscription)
      end

      def fetch_subscription(provider_subscription_id:)
        unsupported(:fetch_subscription)
      end

      def refund_payment(provider_transaction_id:, amount: nil, reason: nil)
        unsupported(:refund_payment)
      end

      def verify_webhook(payload:, headers: {})
        false
      end

      def parse_webhook(payload:, headers: {})
        unsupported(:parse_webhook)
      end

      private

      def header_value(headers, name)
        return if headers.blank?

        normalized = headers.to_h
        normalized[name] ||
          normalized[name.downcase] ||
          normalized[name.upcase] ||
          normalized["HTTP_#{name.upcase.tr('-', '_')}"]
      end

      def unsupported(operation)
        Result.failure(
          code: :unsupported_operation,
          errors: [ "#{name} does not support #{operation}" ]
        )
      end
    end
  end
end

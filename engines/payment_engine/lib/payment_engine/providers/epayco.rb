module PaymentEngine
  module Providers
    # ePayco adapter. All ePayco-specific behavior stays here; the engine's
    # domain models never reference ePayco.
    #
    # Recurring charges require a payment method that supports tokenization and
    # a subscription plan enabled in the merchant account.
    class Epayco < Base
      def self.capabilities
        %i[customers payments refunds tokenization recurring_payments subscription_cancellation webhooks]
      end

      def initialize(settings: {})
        super
        @client = settings[:client] || Client.new(settings: settings)
        @webhook_handler = WebhookHandler.new(settings: settings)
      end

      attr_reader :client, :webhook_handler

      def create_customer(owner:, email: nil, metadata: {})
        client.create_customer(
          customer: {
            name: owner.try(:name).to_s,
            email: email.to_s,
            metadata: metadata
          }
        )
      end

      def create_payment(purchase:, payment:, customer: nil, return_url: nil, confirmation_url: nil)
        response = client.create_payment_session(
          checkout: {
            name: purchase.option_name.presence || purchase.description,
            description: purchase.description,
            invoice: purchase.id.to_s,
            currency: purchase.currency,
            amount: purchase.amount.to_s,
            response: return_url || settings[:response_url],
            confirmation: confirmation_url || settings[:confirmation_url],
            customer: customer
          }.compact
        )

        return response unless response.success?

        Result.success(data: { checkout: response.data, provider_transaction_id: nil })
      end

      def fetch_payment(provider_transaction_id:)
        client.fetch_transaction(provider_transaction_id)
      end

      def create_subscription(subscription:, customer: nil, payment_method_token: nil)
        plan_id = settings[:plan_id] || subscription.metadata["plan_id"]
        if plan_id.blank?
          return Result.failure(code: :missing_plan,
                                errors: [ "ePayco subscriptions require a configured plan_id" ])
        end

        response = client.create_subscription(
          id_plan: plan_id,
          customer: customer,
          token_card: payment_method_token,
          url_confirmation: settings[:confirmation_url]
        )

        return response unless response.success?

        data = response.data.to_h
        Result.success(data: { provider_subscription_id: data["id"] || data[:id] || data["subscriptionId"] })
      end

      def cancel_subscription(provider_subscription_id:, immediately: false)
        client.cancel_subscription(provider_subscription_id)
      end

      def fetch_subscription(provider_subscription_id:)
        client.get("/recurring/subscription/#{provider_subscription_id}")
      end

      def refund_payment(provider_transaction_id:, amount: nil, reason: nil)
        client.refund(
          transactionID: provider_transaction_id,
          amount: amount,
          reason: reason
        )
      end

      def verify_webhook(payload:, headers: {}, raw_body: nil)
        webhook_handler.verify(payload: payload, headers: headers, raw_body: raw_body)
      end

      def parse_webhook(payload:, headers: {}, raw_body: nil)
        webhook_handler.parse(payload: payload, headers: headers, raw_body: raw_body)
      end
    end
  end
end

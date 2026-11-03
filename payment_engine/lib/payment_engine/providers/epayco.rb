module PaymentEngine
  module Providers
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
            name: (owner.respond_to?(:name) ? owner.name : nil).to_s,
            email: email.to_s,
            metadata: metadata
          }
        )
      end

      def create_payment(purchase:, payment:, customer: nil, return_url: nil, confirmation_url: nil, customer_ip: nil)
        name = if purchase.respond_to?(:option_name)
                 purchase.option_name
               elsif purchase.respond_to?(:payment_option) && purchase.payment_option
                 purchase.payment_option.name
               else
                 purchase.try(:commercial_snapshot)&.dig("name")
               end
        description = if purchase.respond_to?(:description)
                        purchase.description
                      else
                        purchase.try(:commercial_snapshot)&.dig("name") || name
                      end

        response = client.create_payment_session(
          {
            checkout_version: "2",
            lang: "ES",
            country: settings[:country] || "CO",
            test: settings[:environment].to_s == "production" ? false : true,
            ip: customer_ip.presence,
            name: name.presence || "Payment",
            description: description,
            invoice: purchase.id.to_s,
            currency: purchase.currency,
            amount: purchase.amount.to_s,
            taxBase: purchase.try(:tax_base).presence || 0,
            tax: purchase.try(:tax).presence || 0,
            response: return_url || settings[:response_url],
            confirmation: confirmation_url || settings[:confirmation_url],
            customer: customer
          }.compact
        )

        # ePayco returns { success: ..., data: { sessionId:, token: } } or an
        # error envelope. Normalize it so the host sees only the session id.
        raw = response.data.to_h
        session_data = raw.is_a?(Hash) ? (raw["data"] || raw["checkout"] || raw) : {}
        checkout = {
          "sessionId" => session_data["sessionId"] || session_data[:sessionId],
          "token" => session_data["token"] || session_data[:token],
          "test" => settings[:environment].to_s != "production"
        }.compact

        PaymentEngine::Result.success(data: { checkout: checkout, provider_transaction_id: nil })
      end

      def fetch_payment(provider_transaction_id:)
        client.fetch_transaction(provider_transaction_id)
      end

      def create_subscription(subscription:, customer: nil, payment_method_token: nil)
        plan_id = if settings[:plan_id].present?
                    settings[:plan_id]
                  elsif subscription.respond_to?(:metadata) && subscription.metadata.is_a?(Hash)
                    subscription.metadata["plan_id"] || subscription.metadata[:plan_id]
                  elsif subscription.respond_to?(:payment_option) && subscription.payment_option.respond_to?(:metadata)
                    nil
                  end
        if plan_id.blank?
          return PaymentEngine::Result.failure(code: :missing_plan,
                                              errors: ["ePayco subscriptions require a configured plan_id"])
        end

        response = client.create_subscription(
          id_plan: plan_id,
          customer: customer,
          token_card: payment_method_token,
          url_confirmation: settings[:confirmation_url]
        )

        return response unless response.success?

        data = response.data.to_h
        PaymentEngine::Result.success(data: { provider_subscription_id: data["id"] || data[:id] || data["subscriptionId"] })
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
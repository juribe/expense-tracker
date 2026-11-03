# frozen_string_literal: true

module PaymentEngine
  module Payments
    # Verifies a payment against the provider (ePayco) using its reference.
    # Used by the checkout result page polling and by scheduled reconciliation.
    class Verify
      def self.call(provider:, reference:, purchase: nil, payment: nil, actor: nil)
        new(provider: provider, reference: reference, purchase: purchase, payment: payment, actor: actor).call
      end

      def initialize(provider:, reference:, purchase: nil, payment: nil, actor: nil)
        @provider = provider
        @reference = reference
        @purchase = purchase
        @payment = payment
        @actor = actor
      end

      def call
        adapter = PaymentEngine.provider(@provider)
        return Result.failure(code: :unknown_provider, errors: ["Proveedor desconocido"]) unless adapter.respond_to?(:fetch_payment)

        result = adapter.fetch_payment(provider_transaction_id: @reference)
        return result unless result.success?

        raw = result.data.to_h { |k, v| [k.to_s, v] }
        # APIFY reports validation errors with HTTP 200 and success=false.
        if raw["success"] == false
          message = raw["textResponse"].presence || "ePayco no pudo consultar la transacción"
          return Result.failure(code: :provider_rejected_query, errors: [message], data: raw)
        end

        data = raw["data"].is_a?(Hash) ? raw["data"].to_h { |k, v| [k.to_s, v] } : raw

        state = map_state(data)
        purchase = resolve_purchase(data)
        return Result.failure(code: :unknown_purchase, errors: ["Compra no encontrada"]) unless purchase

        payment = @payment || purchase.payment || Payment.create!(purchase: purchase, amount: purchase.amount, currency: purchase.currency, status: "pending", provider_code: @provider.to_s)

        ActiveRecord::Base.transaction do
          case state
          when "succeeded"
            payment.update!(provider_code: @provider.to_s, external_reference: @reference, status: "succeeded")
            purchase.update!(status: "paid", payment_id: payment.id) unless purchase.status == "paid"
            Memberships::FulfillPurchase.call(purchase: purchase.reload)
          when "failed"
            payment.update!(provider_code: @provider.to_s, external_reference: @reference, status: "failed")
            purchase.update!(status: "failed") unless purchase.status == "paid"
          when "refunded"
            payment.update!(provider_code: @provider.to_s, external_reference: @reference, status: "refunded")
            purchase.update!(status: "refunded") unless purchase.status == "paid"
          else
            # Pending or unknown: keep the local state and do not overwrite a
            # provider reference already stored by the webhook.
          end
        end

        Result.success(data: { state: state, purchase: purchase, payment: payment, raw: data })
      rescue StandardError => error
        Result.failure(code: :verification_error, errors: [error.message])
      end

      private

      def resolve_purchase(data)
        return @purchase if @purchase

        purchase_id = data["x_id_factura"] || data["x_extra1"] || data["invoice"] || data["purchase_id"] || data["bill"]
        purchase_id = purchase_id.to_i if purchase_id.to_s.match?(/\A\d+\z/)
        Purchase.find_by(id: purchase_id) if purchase_id.present?
      end

      def map_state(data)
        code = data["x_cod_response"] || data["x_cod_respuesta"] || data["cod_response"]
        state = data["x_transaction_state"] || data["transactionState"] || data["x_response"] || data["status"] || data["response"] || data["state"]

        return "succeeded" if code.to_s == "1" || state.to_s.match?(/aceptad|aprobad|approved|success/i)
        return "refunded" if code.to_s == "6" || state.to_s.match?(/reversad|reembols|refunded/i)
        return "failed" if %w[2 4 9 10 11].include?(code.to_s) || state.to_s.match?(/rechazad|fallid|rejected|failed|expirad|cancelad|anulad|cancelled|canceled|voided/i)
        return "pending" if code.to_s == "3" || state.to_s.match?(/pendient|pending/i)

        "pending"
      end
    end
  end
end
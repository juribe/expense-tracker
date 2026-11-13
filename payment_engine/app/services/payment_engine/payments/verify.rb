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

        payment = @payment || purchase.payment

        if (problem = binding_error(data, purchase, payment))
          return problem
        end

        payment ||= Payment.create!(purchase: purchase, amount: purchase.amount, currency: purchase.currency, status: "pending", provider_code: @provider.to_s)

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

        purchase_id = invoice_id(data)
        Purchase.find_by(id: purchase_id) if purchase_id.present?
      end

      # Binds the provider transaction to the local purchase. A reference that
      # is already stored on another payment, or a transaction whose invoice,
      # amount or currency disagree with the purchase, must not settle it.
      def binding_error(data, purchase, payment)
        invoice = invoice_id(data)
        amount = binding_value(data, "x_amount", "amount")
        currency = binding_value(data, "x_currency_code", "currency")

        if invoice.blank? && amount.blank? && currency.blank?
          return mismatch(:unverifiable_transaction, "La transacción no identifica la compra")
        end

        if invoice.present? && invoice.to_s != purchase.id.to_s
          return mismatch(:invoice_mismatch, "La factura no corresponde a la compra")
        end

        if amount.present? && to_decimal(amount) != purchase.amount
          return mismatch(:amount_mismatch, "El monto no corresponde a la compra")
        end

        if currency.present? && !currency.to_s.casecmp?(purchase.currency.to_s)
          return mismatch(:currency_mismatch, "La moneda no corresponde a la compra")
        end

        if reference_used_elsewhere?(payment)
          return mismatch(:reference_already_used, "La referencia ya fue usada por otro pago")
        end

        nil
      end

      def invoice_id(data)
        value = binding_value(data, "x_id_factura", "x_extra1", "invoice", "purchase_id", "bill")
        return if value.blank?

        value.to_s.match?(/\A\d+\z/) ? value.to_i : value
      end

      def binding_value(data, *keys)
        keys.each do |key|
          value = data[key] || data[key.to_sym]
          return value if value.present?
        end
        nil
      end

      def to_decimal(value)
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def reference_used_elsewhere?(payment)
        return false if @reference.blank?

        scope = Payment.where(external_reference: @reference)
        scope = scope.where.not(id: payment.id) if payment
        scope.exists?
      end

      def mismatch(code, message)
        Result.failure(code: code, errors: [ message ])
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
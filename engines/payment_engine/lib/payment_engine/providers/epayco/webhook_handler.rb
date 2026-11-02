require "digest"

module PaymentEngine
  module Providers
    class Epayco < Base
      # Verifies ePayco's confirmation signature and translates its fields into
      # PaymentEngine's internal event format.
      #
      # Signature: SHA256(p_cust_id_cliente^p_key^x_ref_payco^x_transaction_id^x_amount^x_currency_code)
      class WebhookHandler
        STATE_MAP = {
          approved: "payment.approved",
          rejected: "payment.rejected",
          refunded: "payment.refunded",
          pending: "payment.pending"
        }.freeze

        def initialize(settings:)
          @customer_id = (settings[:customer_id] || settings[:p_cust_id_cliente]).to_s
          @p_key = (settings[:p_key] || settings[:private_key]).to_s
        end

        def verify(payload:, headers: {}, raw_body: nil)
          signature = field(payload, "x_signature").to_s
          return false if signature.empty?

          expected = Digest::SHA256.hexdigest(
            [ customer_id, p_key,
              field(payload, "x_ref_payco"),
              field(payload, "x_transaction_id"),
              field(payload, "x_amount"),
              field(payload, "x_currency_code") ].join("^")
          )

          ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        end

        def parse(payload:, headers: {}, raw_body: nil)
          state = state_for(payload)
          event_type = STATE_MAP[state]
          return Result.failure(code: :unsupported_event, errors: [ "unsupported ePayco event" ]) if event_type.blank?

          Result.success(
            data: {
              event_id: event_id(payload, state),
              event_type: event_type,
              provider_transaction_id: field(payload, "x_transaction_id").presence || field(payload, "x_ref_payco"),
              purchase_id: purchase_id(payload),
              amount: amount(payload),
              currency: field(payload, "x_currency_code"),
              paid_at: paid_at(payload),
              payment_method: field(payload, "x_franchise").presence || field(payload, "x_bank_name"),
              failure_reason: field(payload, "x_response_reason_text").presence || field(payload, "x_respuesta"),
              metadata: {
                "epayco_ref" => field(payload, "x_ref_payco"),
                "epayco_response" => field(payload, "x_response"),
                "epayco_response_code" => field(payload, "x_cod_response")
              }
            }
          )
        end

        private

        attr_reader :customer_id, :p_key

        def state_for(payload)
          code = field(payload, "x_cod_response").to_s
          response = "#{field(payload, 'x_response')} #{field(payload, 'x_transaction_state')}".downcase

          return :refunded if code == "6" || response.match?(/reversad|reembols/)
          return :approved if code == "1" || response.match?(/aceptad|aprobad/)
          return :pending if code == "3" || response.match?(/pendient/)
          return :rejected if %w[2 4 9 10 11].include?(code) || response.match?(/rechazad|fallid|expirad|abandonad/)

          :pending
        end

        def event_id(payload, state)
          [ field(payload, "x_ref_payco"), field(payload, "x_transaction_id"), state ].join(":")
        end

        def purchase_id(payload)
          value = field(payload, "x_id_factura").presence || field(payload, "x_extra1").presence
          value.to_s.match?(/\A\d+\z/) ? value.to_i : value
        end

        def amount(payload)
          value = field(payload, "x_amount").to_s
          return if value.empty?

          BigDecimal(value).to_i
        rescue ArgumentError
          nil
        end

        def paid_at(payload)
          value = field(payload, "x_transaction_date").presence || field(payload, "x_fecha_transaccion").presence
          return if value.blank?

          Time.zone ? Time.zone.parse(value) : Time.parse(value)
        rescue ArgumentError
          nil
        end

        def field(payload, key)
          data = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload
          data[key] || data[key.to_sym] || data[key.upcase]
        end
      end
    end
  end
end

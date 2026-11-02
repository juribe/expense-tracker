module PaymentEngine
  module Webhooks
    # Removes card data, tokens and secrets before a payload is persisted.
    # Structure and non-sensitive business fields (ids, amounts, statuses) are
    # preserved so events remain auditable and reprocessable.
    module PayloadRedactor
      SENSITIVE_KEY = /(card|cvv|cvc|token|secret|password|authorization|signature|private_key|p_key)/i
      FILTERED = "[FILTERED]".freeze
      MAX_DEPTH = 12

      module_function

      def redact(value, depth = 0)
        return FILTERED if depth > MAX_DEPTH

        case value
        when Hash
          redact_hash(value, depth)
        when Array
          value.map { |item| redact(item, depth + 1) }
        when ActionController::Parameters
          redact_hash(value.to_unsafe_h, depth)
        else
          value
        end
      end

      def redact_hash(hash, depth)
        hash.each_with_object({}) do |(key, item), result|
          string_key = key.to_s
          result[string_key] = SENSITIVE_KEY.match?(string_key) ? FILTERED : redact(item, depth + 1)
        end
      end
    end
  end
end

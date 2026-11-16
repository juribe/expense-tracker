# frozen_string_literal: true

require "uri"

# RollbarPayloadSanitizer
# Removes financial, personal and credential data from Rollbar payloads.
#
# Example:
#   Rollbar.configure { |config| config.transform = ->(options) { RollbarPayloadSanitizer.call(options) } }
module ErrorReporting
  class RollbarPayloadSanitizer
    MAX_MESSAGE_LENGTH = 500
    FILTERED = "[FILTERED]"
    TRUNCATED = "...[truncated]"

    SENSITIVE_KEY_PATTERN = /
      (?:\A|_)
      (?:
        password|passwd|secret|token|api_key|apikey|
        authorization|cookie|cookies|session|session_id|csrf|authenticity_token|
        email|email_address|phone|phone_number|mobile|address|ssn|
        cvv|cvc|card|card_number|account|account_number|iban|routing|routing_number|
        credit|credit_limit|interest_rate|installment|principal|
        description|content|body|body_text|html|text|transcript|raw_body|payload|headers|
        response|raw_response|api_response|external_response|error_message|last_error|
        subject|sender|recipient|from_address|to_address|bank_account|bank_statement|statement|
        file|files|file_data|image_data|audio_data|attachment|attachments|upload|uploads|
        amount|balance|total|subtotal|
        merchant|category|transaction|transactions|expense|expenses|income|incomes|
        salary|employer|reference|identifier|fingerprint|last4|last_four|
        public_key|public_key_credential|recovery_code|code_digest|
        totp_code|otp_code|totp_secret|
        whatsapp|whatsapp_access_token|whatsapp_token|
        epayco|epayco_api_key|epayco_private_key|epayco_customer_id|epayco_p_key|
        inbound_email|inbound_email_secret|inbound_email_token|
        arguments|params|parameters|locals|
        full_name|first_name|last_name|user_name|username
      )
      (?:\z|_)
    /ix

    EMAIL_PATTERN = /[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i
    CARD_PATTERN = /\b(?:\d[ -]?){12,19}\b/
    LONG_NUMBER_PATTERN = /\b\d{7,}\b/
    PHONE_PATTERN = /\+?\d[\d\s().-]{7,}\d/
    BEARER_PATTERN = /\b(?:Bearer|Basic|Token)\s+[A-Za-z0-9\-._~+\/]+=*/i
    JWT_PATTERN = /\beyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\b/
    SECRET_ASSIGNMENT_PATTERN = /
      \b(password|passwd|secret|token|api[_-]?key|authorization|access[_-]?token|refresh[_-]?token)\b
      \s*[:=]\s*
      ("[^"]*"|'[^']*'|[^\s,;]+)
    /ix

    SAFE_REQUEST_KEYS = %w[url method request_id].freeze

    def self.call(options)
      new(options).call
    end

    def initialize(options)
      @options = options || {}
      @payload = fetch(@options, :payload)
    end

    def call
      return payload unless payload.is_a?(Hash)

      data = fetch(payload, :data)
      return payload unless data.is_a?(Hash)

      sanitize_request(data)
      sanitize_person(data)
      sanitize_body(data)
      sanitize_nested(data, :custom)
      sanitize_nested(data, :context)

      payload
    end

    private

    attr_reader :options, :payload

    def sanitize_request(data)
      request = fetch(data, :request)
      return unless request.is_a?(Hash)

      request.keys.each do |key|
        normalized = key.to_s.downcase

        if SAFE_REQUEST_KEYS.include?(normalized)
          request[key] = sanitize_url(request[key]) if normalized == "url"
        else
          request.delete(key)
        end
      end

      delete(data, :request) if request.empty?
    end

    def sanitize_person(data)
      person = fetch(data, :person)
      return unless person.is_a?(Hash)

      person_id = fetch(person, :id)
      person.clear

      if person_id.nil? || person_id.to_s.empty?
        delete(data, :person)
      else
        set(person, :id, person_id.to_s)
      end
    end

    def sanitize_body(data)
      body = fetch(data, :body)

      if body.is_a?(String)
        set(data, :body, sanitize_text(body))
        return
      end

      return unless body.is_a?(Hash)

      sanitize_trace(fetch(body, :trace))
      Array(fetch(body, :trace_chain)).each { |trace| sanitize_trace(trace) }
      sanitize_message_payload(fetch(body, :message))
    end

    def sanitize_trace(trace)
      return unless trace.is_a?(Hash)

      exception = fetch(trace, :exception)
      if exception.is_a?(Hash)
        message = fetch(exception, :message)
        set(exception, :message, sanitize_text(message)) if message.is_a?(String)
        sanitize_recursively(exception)
      end

      sanitize_nested(trace, :extra)

      Array(fetch(trace, :frames)).each { |frame| sanitize_recursively(frame) }
    end

    def sanitize_message_payload(message)
      return unless message.is_a?(Hash)

      body = fetch(message, :body)
      set(message, :body, sanitize_text(body)) if body.is_a?(String)
      sanitize_nested(message, :extra)
    end

    def sanitize_nested(hash, key)
      return unless hash.is_a?(Hash)

      value = fetch(hash, key)
      case value
      when String
        set(hash, key, sanitize_text(value))
      when Hash, Array
        sanitize_recursively(value)
      end
    end

    def sanitize_recursively(value, seen = {})
      case value
      when Hash
        return value if seen[value.object_id]

        seen[value.object_id] = true
        value.keys.each do |key|
          if sensitive_key?(key)
            value.delete(key)
          else
            value[key] = sanitize_recursively(value[key], seen)
          end
        end
        value
      when Array
        return value if seen[value.object_id]

        seen[value.object_id] = true
        value.map! { |item| sanitize_recursively(item, seen) }
      when String
        sanitize_text(value)
      else
        value
      end
    end

    def sensitive_key?(key)
      SENSITIVE_KEY_PATTERN.match?(key.to_s)
    end

    def sanitize_url(url)
      return url unless url.is_a?(String)

      uri = URI.parse(url)
      uri.user = nil
      uri.password = nil
      uri.query = nil
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      url.split("?", 2).first
    end

    def sanitize_text(value)
      return value unless value.is_a?(String)

      sanitized = value.gsub(SECRET_ASSIGNMENT_PATTERN) do
        "#{Regexp.last_match(1)}=#{FILTERED}"
      end
      sanitized = sanitized.gsub(BEARER_PATTERN, FILTERED)
      sanitized = sanitized.gsub(JWT_PATTERN, FILTERED)
      sanitized = sanitized.gsub(EMAIL_PATTERN, FILTERED)
      sanitized = sanitized.gsub(CARD_PATTERN, FILTERED)
      sanitized = sanitized.gsub(PHONE_PATTERN, FILTERED)
      sanitized = sanitized.gsub(LONG_NUMBER_PATTERN, FILTERED)

      truncate(sanitized)
    end

    def truncate(value)
      return value if value.length <= MAX_MESSAGE_LENGTH

      "#{value[0, MAX_MESSAGE_LENGTH - TRUNCATED.length]}#{TRUNCATED}"
    end

    def fetch(hash, key)
      return unless hash.is_a?(Hash)

      hash.key?(key) ? hash[key] : hash[key.to_s]
    end

    def set(hash, key, value)
      hash.delete(key.to_s)
      hash[key] = value
    end

    def delete(hash, key)
      hash.delete(key)
      hash.delete(key.to_s)
    end
  end
end

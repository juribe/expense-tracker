# frozen_string_literal: true

module MailInbound
  # Reads the relay's Authentication-Results header. Inbound email may only
  # auto-create records when the sender domain passed DKIM or DMARC; the MIME
  # From header alone is not proof of authorship.
  #
  # Example: MailInbound::SenderAuthentication.authenticated?(message[:headers])
  class SenderAuthentication
    PASS_PATTERN = /(?:^|[;\s])(?:dkim|dmarc)\s*=\s*pass\b/i

    class << self
      def authenticated?(headers)
        authentication_results(headers).any? { |value| value.match?(PASS_PATTERN) }
      end

      private

      def authentication_results(headers)
        if headers.is_a?(Hash)
          key = headers.keys.find { |name| name.to_s.casecmp?("authentication-results") }
          return key ? [ headers[key].to_s ] : []
        end

        Array(headers).filter_map do |header|
          next unless (header["name"] || header[:name]).to_s.casecmp?("authentication-results")

          (header["value"] || header[:value]).to_s
        end
      end
    end
  end
end

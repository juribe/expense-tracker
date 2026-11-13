# frozen_string_literal: true

module MailInbound
  # Reads the relay's Authentication-Results header. Only the first header,
  # added by the inbound relay (Email Routing, authserv-id mx.cloudflare.net),
  # is trustworthy: later ones may have been supplied by the sender. A message
  # may only auto-create records when that result reports dmarc=pass, which
  # binds the verdict to the From domain.
  #
  # Example: MailInbound::SenderAuthentication.authenticated?(message[:headers])
  class SenderAuthentication
    DMARC_PASS_PATTERN = /\bdmarc\s*=\s*pass\b/i
    DEFAULT_AUTHSERV_ID = "mx.cloudflare.net"

    class << self
      def authenticated?(headers)
        value = first_authentication_results(headers)
        return false if value.blank?

        authserv_id, results = value.split(";", 2)
        return false unless authserv_id.to_s.strip.casecmp?(trusted_authserv_id)
        return false if results.blank?

        results.match?(DMARC_PASS_PATTERN)
      end

      private

      def trusted_authserv_id
        ENV.fetch("INBOUND_EMAIL_AUTHSERV_ID", DEFAULT_AUTHSERV_ID).to_s
      end

      def first_authentication_results(headers)
        if headers.is_a?(Hash)
          key = headers.keys.find { |name| name.to_s.casecmp?("authentication-results") }
          return key ? headers[key].to_s : nil
        end

        Array(headers).each do |header|
          next unless (header["name"] || header[:name]).to_s.casecmp?("authentication-results")

          return (header["value"] || header[:value]).to_s
        end

        nil
      end
    end
  end
end

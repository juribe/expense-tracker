# frozen_string_literal: true

require "timeout"

module MailInbound
  module Providers
    class Resend
      # ReceivingClient
      # Fetches a received email through Resend's official Receiving API.
      class ReceivingClient
        REQUEST_TIMEOUT_SECONDS = 30

        def initialize(api_key: ENV["RESEND_API_KEY"])
          @api_key = api_key
        end

        def fetch(email_id)
          raise ConfigurationError, "RESEND_API_KEY is not configured" if @api_key.blank?
          raise InvalidPayload, "email_id is required" if email_id.blank?

          ::Resend.api_key = @api_key
          response = Timeout.timeout(REQUEST_TIMEOUT_SECONDS) do
            ::Resend::Emails::Receiving.get(email_id)
          end
          normalize(response)
        rescue ::Resend::Error::NotFoundError
          raise InvalidPayload, "received email was not found"
        rescue Timeout::Error
          raise ProviderError, "Resend Receiving API timed out"
        rescue ::Resend::Error => e
          raise ProviderError, "Resend Receiving API failed (#{e.message})"
        rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
          raise ProviderError, "Resend Receiving API connection failed (#{e.class})"
        end

        private

        def normalize(response)
          data = response.respond_to?(:to_h) ? response.to_h : response
          raise ProviderError, "Resend Receiving API returned an unexpected response" unless data.is_a?(Hash)

          data.deep_stringify_keys
        end
      end
    end
  end
end

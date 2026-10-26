# frozen_string_literal: true

require "digest"
require "openssl"

module MailInbound
  module Providers
    class Cloudflare
  # SignatureVerifier
  # Authenticates Cloudflare Email Worker requests with a timestamped HMAC.
  #
  # The signed payload is:
  #   "<timestamp>\n<lowercased recipient>\n<sha256(raw MIME)>"
  #
  # Example:
  #   MailInbound::Providers::Cloudflare::SignatureVerifier.valid?(
  #     secret: ENV["INBOUND_EMAIL_SECRET"], timestamp:, recipient:,
  #     signature:, body: request.raw_post
  #   )
  class SignatureVerifier
    DEFAULT_MAX_SKEW_SECONDS = 300

    class << self
      def valid?(secret:, timestamp:, recipient:, signature:, body:, previous_secret: nil,
                max_skew: DEFAULT_MAX_SKEW_SECONDS)
        new(
          secret: secret,
          previous_secret: previous_secret,
          timestamp: timestamp,
          recipient: recipient,
          signature: signature,
          body: body,
          max_skew: max_skew
        ).valid?
      end

      def expected_signature(secret:, timestamp:, recipient:, body:)
        return "" if secret.blank?

        signed_payload = [
          timestamp.to_s,
          normalize_recipient(recipient),
          Digest::SHA256.hexdigest(body.to_s)
        ].join("\n")

        OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
      end

      def normalize_recipient(recipient)
        recipient.to_s.strip.downcase
      end
    end

    def initialize(secret:, timestamp:, recipient:, signature:, body:, previous_secret: nil,
                   max_skew: DEFAULT_MAX_SKEW_SECONDS)
      @secret = secret.to_s
      @previous_secret = previous_secret.to_s
      @timestamp = timestamp.to_s
      @recipient = self.class.normalize_recipient(recipient)
      @signature = signature.to_s
      @body = body.to_s
      @max_skew = max_skew.to_i.clamp(30, 3600)
    end

    def valid?
      return false if @secret.blank? || @signature.blank? || @recipient.blank?
      return false unless timestamp_valid?

      secrets.any? do |secret|
        ActiveSupport::SecurityUtils.secure_compare(
          self.class.expected_signature(
            secret: secret, timestamp: @timestamp, recipient: @recipient, body: @body
          ),
          @signature
        )
      end
    end

    private

    def secrets
      [ @secret, @previous_secret ].reject(&:blank?).uniq
    end

    def timestamp_valid?
      timestamp = Integer(@timestamp, exception: false)
      return false if timestamp.nil? || timestamp <= 0

      (Time.current.to_i - timestamp).abs <= @max_skew
    end
  end
    end
  end
end

# frozen_string_literal: true

require "cgi"
require "uri"

module MailInbound
  # Validates provider confirmation links before exposing them to the browser.
  class ConfirmationUrlValidator
    ALLOWED_HOSTS = %w[mail.google.com mail-settings.google.com].freeze

    def self.call(url)
      return nil if url.blank?

      uri = URI.parse(CGI.unescapeHTML(url.to_s.strip))
      return nil unless uri.is_a?(URI::HTTPS)
      return nil if uri.host.blank?
      return nil if uri.userinfo.present?
      return nil if uri.port != 443
      return nil if uri.path.blank?

      host = uri.host.downcase.delete_suffix(".")
      return nil unless ALLOWED_HOSTS.include?(host)

      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      nil
    end
  end
end

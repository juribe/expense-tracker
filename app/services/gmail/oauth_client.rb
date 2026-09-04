# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Gmail
  # Minimal Google OAuth2 client (no external gems). Handles building the
  # authorization URL, exchanging the authorization code, refreshing tokens
  # and fetching basic profile info.
  #
  # Configuration comes from ENV:
  #   GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET  (required)
  class OauthClient
    AUTH_BASE = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"

    SCOPES = [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/userinfo.email",
      "openid"
    ].freeze

    class Error < StandardError; end
    class ConfigurationError < Error; end

    class << self
      def configured?
        client_id.present? && client_secret.present?
      end

      def authorize_url(redirect_uri:, state:)
        raise_configuration_error! unless configured?

        params = {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: SCOPES.join(" "),
          access_type: "offline",
          prompt: "consent",
          state: state
        }
        "#{AUTH_BASE}?#{URI.encode_www_form(params)}"
      end

      # Returns { access_token:, refresh_token:, expires_at:, id_token: }
      def exchange_code(code:, redirect_uri:)
        response = post_token(
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code"
        )
        parse_token_response(response)
      end

      # Returns { access_token:, expires_at:, refresh_token: (optional) }
      def refresh(refresh_token)
        response = post_token(
          refresh_token: refresh_token,
          client_id: client_id,
          client_secret: client_secret,
          grant_type: "refresh_token"
        )
        data = parse_token_response(response)
        { access_token: data[:access_token], expires_at: data[:expires_at], refresh_token: nil }
      end

      # Returns { sub:, email: } for the given access token.
      def userinfo(access_token)
        uri = URI(USERINFO_URL)
        request = Net::HTTP::Get.new(uri.request_uri)
        request["Authorization"] = "Bearer #{access_token}"
        body = perform(Net::HTTP.new(uri.host, uri.port), request)

        {
          sub: body["sub"].to_s,
          email: body["email"].to_s
        }
      rescue JSON::ParserError => e
        raise Error, "invalid userinfo response (#{e.message})"
      end

      private

      def client_id
        ENV["GOOGLE_CLIENT_ID"].presence
      end

      def client_secret
        ENV["GOOGLE_CLIENT_SECRET"].presence
      end

      def raise_configuration_error!
        raise ConfigurationError,
              "Google OAuth is not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
      end

      def post_token(payload)
        uri = URI(TOKEN_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 25

        request = Net::HTTP::Post.new(uri.request_uri)
        request.set_form_data(payload)
        perform(http, request)
      end

      def perform(http, request)
        http.use_ssl = true
        response = http.request(request)
        unless response.code.to_i == 200
          snippet = response.body.to_s[0, 300]
          raise Error, "Google OAuth request failed (HTTP #{response.code}): #{snippet}"
        end

        JSON.parse(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
        raise Error, "Google OAuth request failed (#{e.message})"
      end

      def parse_token_response(body)
        {
          access_token: body["access_token"].to_s.presence || raise(Error, "missing access_token"),
          refresh_token: body["refresh_token"],
          expires_at: body["expires_in"] ? Time.current + body["expires_in"].to_i.seconds : nil,
          id_token: body["id_token"]
        }
      end
    end
  end
end

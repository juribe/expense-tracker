require "json"
require "net/http"
require "uri"
require "base64"

module PaymentEngine
  module Providers
    class Epayco < Base
      # REST client for ePayco. ePayco exposes two complementary APIs:
      #
      # - APIFY (payments, sessions, transactions): https://apify.epayco.co
      #   Authenticated with a Bearer token issued by POST {APIFY}/login via
      #   HTTP Basic auth (public_key:private_key).
      # - Secure/api (tokenization, customers, recurring plans and
      #   subscriptions): https://api.secure.payco.co
      #   Also Bearer, but the login endpoint is POST /v1/auth/login with a
      #   JSON body { public_key, private_key }.
      #
      # Credentials are read from engine configuration and never logged.
      class Client
        APIFY_BASE_URL = "https://apify.epayco.co".freeze
        SECURE_BASE_URL = "https://api.secure.payco.co".freeze
        OPEN_TIMEOUT = 10
        READ_TIMEOUT = 20

        def initialize(settings:, base_url: nil)
          @public_key = settings[:public_key]
          @private_key = settings[:private_key]
          @apify_base_url = base_url || settings[:base_url] || APIFY_BASE_URL
          @secure_base_url = settings[:secure_base_url] || SECURE_BASE_URL
          @api_token = nil
          @api_token_expires_at = nil
          @secure_token = nil
          @secure_token_expires_at = nil
        end

        # ---------- APIFY (Bearer via HTTP Basic login) ----------

        def login
          post("/login", nil, base: @apify_base_url, authenticated: false, basic_auth: true)
        end

        def create_payment_session(payload)
          post("/payment/session/create", payload, base: @apify_base_url)
        end

        def fetch_transaction(provider_transaction_id)
          post("/transaction/detail", { filter: { referencePayco: provider_transaction_id } }, base: @apify_base_url)
        end

        def create_token(payload)
          post("/token/card", payload, base: @apify_base_url)
        end

        def create_customer(payload)
          post("/token/customer", payload, base: @apify_base_url)
        end

        def transaction_response(provider_transaction_id)
          get("/transaction/detail", { filter: { referencePayco: provider_transaction_id } }, base: @apify_base_url)
        end

        def refund(payload)
          post("/transaction/reversion", payload, base: @apify_base_url)
        end

        # ---------- Secure/api (Bearer via /v1/auth/login) ----------

        def secure_login
          post("/v1/auth/login", { public_key: @public_key, private_key: @private_key }, base: @secure_base_url, authenticated: false)
        end

        def create_subscription(payload)
          post("/recurring/v1/subscription/create", payload, base: @secure_base_url)
        end

        def cancel_subscription(provider_subscription_id)
          post("/recurring/v1/subscription/cancel",
               { id: provider_subscription_id, public_key: @public_key },
               base: @secure_base_url)
        end

        def fetch_subscription(provider_subscription_id)
          get("/recurring/v1/subscription/#{provider_subscription_id}/#{@public_key}/", {}, base: @secure_base_url)
        end

        # ---------- Low-level helpers ----------

        def post(path, body, base:, authenticated: true, basic_auth: false)
          request(Net::HTTP::Post, path, body: body, base: base, authenticated: authenticated, basic_auth: basic_auth)
        end

        def get(path, params = {}, base: @apify_base_url, authenticated: true)
          request(Net::HTTP::Get, path, params: params, base: base, authenticated: authenticated)
        end

        private

        def request(http_class, path, body: nil, params: nil, base:, authenticated: true, basic_auth: false)
          uri = URI.join(base, path)
          uri.query = URI.encode_www_form(params) if params.present?

          request = http_class.new(uri)
          request["Content-Type"] = "application/json"
          request["Accept"] = "application/json"
          if authenticated
            request["Authorization"] = "Bearer #{bearer_token(base)}"
          elsif basic_auth
            request["Authorization"] = "Basic #{Base64.strict_encode64("#{@public_key}:#{@private_key}")}"
          end
          request.body = JSON.generate(body) if body

          response = Net::HTTP.start(
            uri.host, uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: OPEN_TIMEOUT,
            read_timeout: READ_TIMEOUT
          ) { |http| http.request(request) }

          parse_response(response)
        rescue StandardError => error
          PaymentEngine::Result.failure(code: :provider_network_error,
                                       errors: ["ePayco request failed: #{error.class}"])
        end

        def bearer_token(base)
          if base.to_s.include?("secure.payco.co")
            secure_token
          else
            apify_token
          end
        end

        def apify_token
          return @api_token if @api_token.present? && @api_token_expires_at.present? && @api_token_expires_at > Time.now

          result = login
          raise ResultError, result.error_message unless result.success?

          data = result.data.to_h
          @api_token = data["token"] || data["bearer_token"] || data[:token] || data[:bearer_token]
          @api_token_expires_at = Time.now + TOKEN_TTL
          @api_token
        end

        def secure_token
          return @secure_token if @secure_token.present? && @secure_token_expires_at.present? && @secure_token_expires_at > Time.now

          result = secure_login
          raise ResultError, result.error_message unless result.success?

          data = result.data.to_h
          @secure_token = data["token"] || data["bearer_token"] || data[:token] || data[:bearer_token]
          @secure_token_expires_at = Time.now + TOKEN_TTL
          @secure_token
        end

        TOKEN_TTL = 55 * 60

        def parse_response(response)
          parsed = JSON.parse(response.body.presence || "{}")
          if response.is_a?(Net::HTTPSuccess)
            PaymentEngine::Result.success(data: parsed)
          else
            PaymentEngine::Result.failure(code: :provider_http_error,
                                         errors: ["ePayco responded with HTTP #{response.code}"],
                                         data: parsed)
          end
        rescue JSON::ParserError
          PaymentEngine::Result.failure(code: :provider_invalid_response,
                                       errors: ["ePayco returned an invalid response"])
        end

        class ResultError < StandardError; end
      end
    end
  end
end
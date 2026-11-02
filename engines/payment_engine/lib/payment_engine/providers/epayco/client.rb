require "json"
require "net/http"
require "uri"

module PaymentEngine
  module Providers
    class Epayco < Base
      # Thin HTTP client for ePayco's APIFY REST API. Credentials are read from
      # engine configuration and never logged. Endpoint paths are configurable
      # because ePayco evolves its API; verify them against the current docs
      # before going live.
      class Client
        BASE_URL = "https://api.epayco.co".freeze
        TOKEN_TTL = 55 * 60

        def initialize(settings:, base_url: nil)
          @public_key = settings[:public_key]
          @private_key = settings[:private_key]
          @base_url = base_url || settings[:base_url] || BASE_URL
          @token = nil
          @token_expires_at = nil
        end

        def login
          post("/login", { public_key: @public_key, private_key: @private_key }, authenticated: false)
        end

        def create_customer(payload)
          post("/customer/create", payload)
        end

        def create_token(payload)
          post("/token/create", payload)
        end

        def create_payment_session(payload)
          post("/payment/session/create", payload)
        end

        def fetch_transaction(provider_transaction_id)
          get("/transaction/detail", { transactionID: provider_transaction_id })
        end

        def create_plan(payload)
          post("/recurring/plan/create", payload)
        end

        def create_subscription(payload)
          post("/recurring/subscription/create", payload)
        end

        def cancel_subscription(provider_subscription_id)
          post("/recurring/subscription/cancel", { id: provider_subscription_id })
        end

        def refund(payload)
          post("/transaction/refund", payload)
        end

        def post(path, body, authenticated: true)
          request(Net::HTTP::Post, path, body: body, authenticated: authenticated)
        end

        def get(path, params = {}, authenticated: true)
          request(Net::HTTP::Get, path, params: params, authenticated: authenticated)
        end

        private

        def request(http_class, path, body: nil, params: nil, authenticated: true)
          uri = URI.join(@base_url, path)
          uri.query = URI.encode_www_form(params) if params.present?

          request = http_class.new(uri)
          request["Content-Type"] = "application/json"
          request["Accept"] = "application/json"
          request["Authorization"] = "Bearer #{access_token}" if authenticated
          request.body = JSON.generate(body) if body

          response = Net::HTTP.start(
            uri.host, uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 10,
            read_timeout: 20
          ) { |http| http.request(request) }

          parse_response(response)
        rescue StandardError => error
          Result.failure(code: :provider_network_error,
                         errors: [ "ePayco request failed: #{error.class}" ])
        end

        def access_token
          return @token if @token.present? && @token_expires_at.present? && @token_expires_at > Time.now

          result = login
          raise ResultError, result.error_message unless result.success?

          data = result.data.to_h
          @token = data["token"] || data[:token]
          @token_expires_at = Time.now + TOKEN_TTL
          @token
        end

        def parse_response(response)
          parsed = JSON.parse(response.body.presence || "{}")
          if response.is_a?(Net::HTTPSuccess)
            Result.success(data: parsed)
          else
            Result.failure(code: :provider_http_error,
                           errors: [ "ePayco responded with HTTP #{response.code}" ],
                           data: parsed)
          end
        rescue JSON::ParserError
          Result.failure(code: :provider_invalid_response,
                         errors: [ "ePayco returned an invalid response" ])
        end

        class ResultError < StandardError; end
      end
    end
  end
end

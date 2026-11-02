module PaymentEngine
  class WebhooksController < ApplicationController
    skip_forgery_protection

    def create
      result = Webhooks::Receive.call(
        provider_name: params[:provider],
        payload: request.request_parameters,
        headers: request.headers.to_h,
        raw_body: request.raw_post
      )

      if result.success?
        render json: { status: "ok" }, status: :ok
      else
        render json: { error: result.error_message }, status: error_status(result)
      end
    end

    private

    def error_status(result)
      case result.code
      when :invalid_signature then :unauthorized
      when :unknown_provider then :not_found
      else :unprocessable_entity
      end
    end
  end
end

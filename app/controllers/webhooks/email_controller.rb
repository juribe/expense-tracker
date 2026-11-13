# frozen_string_literal: true

module Webhooks
  # EmailController
  # HTTP boundary for provider-neutral inbound email webhooks.
  # Signature validation, delivery persistence and provider details live in
  # MailInboundService and its provider strategies.
  class EmailController < ActionController::Base
    MAX_PAYLOAD_BYTES = 25.megabytes

    # A compromised or misconfigured relay could otherwise flood the endpoint.
    rate_limit to: 30, within: 1.minute, only: :create, store: RateLimitProxy.new

    HTTP_STATUS = {
      accepted: :accepted,
      duplicate: :ok,
      invalid_signature: :unauthorized,
      unknown_recipient: :forbidden,
      invalid_payload: :unprocessable_entity,
      unsupported_media_type: :unsupported_media_type,
      payload_too_large: 413,
      configuration_error: :internal_server_error,
      queue_unavailable: :service_unavailable
    }.freeze

    skip_before_action :verify_authenticity_token, only: :create

    def create
      # Reject before the HMAC and the provider parse: the size cap belongs at
      # the HTTP boundary, not inside the provider.
      if payload_too_large?
        return render json: { status: "payload_too_large" }, status: 413
      end

      result = MailInboundService.new.accept(mail_inbound_request)
      render_result(result)
    end

    private

    def payload_too_large?
      request.content_length.to_i > max_payload_bytes ||
        request.raw_post.bytesize > max_payload_bytes
    end

    def max_payload_bytes
      ENV.fetch("INBOUND_EMAIL_MAX_BYTES", MAX_PAYLOAD_BYTES).to_i.clamp(1, MAX_PAYLOAD_BYTES)
    end

    def mail_inbound_request
      raw_body = request.raw_post
      MailInbound::Request.new(
        raw_body: raw_body,
        headers: request.headers.to_h,
        params: params.to_unsafe_h,
        content_type: request.content_type
      )
    end

    def render_result(result)
      status = HTTP_STATUS.fetch(result.status, :internal_server_error)
      payload = { status: result.status }
      payload[:id] = result.delivery.id if result.delivery

      error = result.status != :accepted && result.status != :duplicate
      payload[:error] = result.status.to_s if error
      Rails.logger.warn("[MailInbound] status=#{result.status} error=#{result.error&.class}") if error
      render json: payload, status: status
    end
  end
end

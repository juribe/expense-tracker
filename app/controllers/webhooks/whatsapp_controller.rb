# frozen_string_literal: true

module Webhooks
  class WhatsappController < ActionController::Base
    MAX_PAYLOAD_BYTES = 1_000_000

    # Public endpoint: signature-verified but still flood-able; a rough
    # per-IP ceiling keeps a compromised sender from stacking webhook jobs.
    rate_limit to: 30, within: 1.minute, only: :webhook, store: RateLimitProxy.new

    skip_before_action :verify_authenticity_token, only: [ :webhook, :verify ]

    def webhook
      if request.content_length.to_i > MAX_PAYLOAD_BYTES
        Rails.logger.warn "Rejected oversized WhatsApp webhook payload"
        render json: { error: "Payload too large" }, status: 413
        return
      end

      unless verify_signature
        render json: { error: "Invalid signature" }, status: :unauthorized
        return
      end
      Rails.logger.info "Received webhook request"
      WhatsappWebhookJob.perform_later(request.raw_post)
      render json: { status: "success" }, status: :ok
    end

    def verify
      token = ENV["WHATSAPP_VERIFY_TOKEN"]
      provided = params["hub.verify_token"].to_s
      if token.present? && params["hub.mode"] == "subscribe" &&
          ActiveSupport::SecurityUtils.secure_compare(token, provided)
        render plain: params["hub.challenge"]
      else
        render plain: "Verification failed", status: 403
      end
    end

    private

    def verify_signature
      payload = request.raw_post
      signature_header = request.headers["X-Hub-Signature-256"] || request.headers["X-Hub-Signature"]
      return false unless signature_header.present?

      secret = ENV["FB_APP_SECRET"]
      return false if secret.blank?

      digest = OpenSSL::Digest::SHA256.new
      expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(digest, secret, payload)

      ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature_header)
    end
  end
end

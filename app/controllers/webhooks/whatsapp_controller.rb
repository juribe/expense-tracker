# frozen_string_literal: true
module Webhooks
  class WhatsappController < ActionController::Base
    skip_before_action :verify_authenticity_token, only: [:webhook, :verify]

    def webhook
      unless verify_signature
        render json: { error: 'Invalid signature' }, status: :unauthorized
        return
      end
      Rails.logger.info 'Received webhook request'
      WhatsappWebhookJob.perform_later(request.raw_post)
      render json: { status: 'success' }, status: :ok
    end

    def verify
      verify_token = ENV['WHATSAPP_VERIFY_TOKEN']
      if params["hub.mode"] == "subscribe" && params["hub.verify_token"] == verify_token
        render plain: params["hub.challenge"]
      else
        render plain: "Verification failed", status: 403
      end
    end

    private

    def verify_signature
      payload = request.raw_post
      signature_header = request.headers['X-Hub-Signature-256'] || request.headers['X-Hub-Signature']
      return false unless signature_header.present?

      secret = ENV['FB_APP_SECRET']
      digest = OpenSSL::Digest::SHA256.new
      expected_signature = 'sha256=' + OpenSSL::HMAC.hexdigest(digest, secret, payload)

      ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature_header)
    end
  end
end

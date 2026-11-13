# frozen_string_literal: true

module PaymentEngine
  module Admin
    class WebhookEventsController < BaseController
      before_action :set_record, only: [:show, :reprocess]

      def index
        @records = WebhookEvent.order(created_at: :desc)
        @records = @records.where(provider_code: params[:provider]) if params[:provider].present?
        @records = @records.where(status: params[:status]) if params[:status].present?
        @records = @records.where(event_type: params[:event_type]) if params[:event_type].present?
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      def reprocess
        data = normalized_payload
        if data.nil?
          redirect_to admin_webhook_event_path(@record), alert: "No se pudo normalizar el evento."
          return
        end

        result = Webhooks::Process.call(webhook_event: @record, data: data, actor: current_host_user)
        if result.success?
          redirect_to admin_webhook_event_path(@record), notice: "Reprocesado."
        else
          redirect_to admin_webhook_event_path(@record), alert: result.errors.join(", ")
        end
      end

      private

      def set_record
        @record = WebhookEvent.find(params[:id])
      end

      # The stored payload is the provider's raw notification; normalize it the
      # same way the webhook endpoint does before replaying it.
      def normalized_payload
        adapter = PaymentEngine.provider(@record.provider_code)
        return @record.payload unless adapter.respond_to?(:parse_webhook)

        parsed = adapter.parse_webhook(payload: @record.payload || {}, headers: {}, raw_body: nil)
        parsed.success? ? parsed.data : nil
      rescue PaymentEngine::UnknownProviderError, PaymentEngine::ConfigurationError
        nil
      end
    end
  end
end

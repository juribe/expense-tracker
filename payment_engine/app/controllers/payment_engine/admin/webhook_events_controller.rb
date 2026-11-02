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
        result = Webhooks::Process.call(webhook_event: @record, actor: current_host_user)
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
    end
  end
end

# frozen_string_literal: true

module PaymentEngine
  module Admin
    class PaymentsController < BaseController
      before_action :set_record, only: [:show]

      def index
        @records = Payment.includes(:purchase).order(created_at: :desc)
        @records = @records.where(status: params[:status]) if params[:status].present?
        @records = @records.where(provider_code: params[:provider]) if params[:provider].present?
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      def refund
        payment = Payment.find(params[:id])
        result = Payments::Refund.call(payment: payment, actor: current_host_user, reason: params[:reason])
        if result.success?
          redirect_to admin_payment_path(payment), notice: "Reembolso solicitado."
        else
          redirect_to admin_payment_path(payment), alert: result.errors.join(", ")
        end
      end

      private

      def set_record
        @record = Payment.find(params[:id])
      end
    end
  end
end

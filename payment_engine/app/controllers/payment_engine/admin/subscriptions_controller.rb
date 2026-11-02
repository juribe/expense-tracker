# frozen_string_literal: true

module PaymentEngine
  module Admin
    class SubscriptionsController < BaseController
      before_action :set_record, only: [:show, :cancel, :resume]

      def index
        @records = Subscription.includes(:payment_option, :owner).order(created_at: :desc)
        @records = @records.where(status: params[:status]) if params[:status].present?
        @records = @records.where(provider_code: params[:provider]) if params[:provider].present?
        @records = @records.where(payment_option_id: params[:payment_option_id]) if params[:payment_option_id].present?
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      def cancel
        result = Subscriptions::Cancel.call(subscription: @record, actor: current_host_user, reason: params[:reason])
        if result.success?
          redirect_to admin_subscription_path(@record), notice: "Cancelada."
        else
          redirect_to admin_subscription_path(@record), alert: result.errors.join(", ")
        end
      end

      def resume
        result = Subscriptions::Resume.call(subscription: @record, actor: current_host_user, reason: params[:reason])
        if result.success?
          redirect_to admin_subscription_path(@record), notice: "Reanudada."
        else
          redirect_to admin_subscription_path(@record), alert: result.errors.join(", ")
        end
      end

      private

      def set_record
        @record = Subscription.find(params[:id])
      end
    end
  end
end

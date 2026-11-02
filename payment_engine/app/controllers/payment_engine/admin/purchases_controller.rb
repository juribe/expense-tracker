# frozen_string_literal: true

module PaymentEngine
  module Admin
    class PurchasesController < BaseController
      before_action :set_record, only: [:show]

      def index
        @records = Purchase.includes(:payment_option, :owner).order(created_at: :desc)
        @records = @records.where(status: params[:status]) if params[:status].present?
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      private

      def set_record
        @record = Purchase.find(params[:id])
      end
    end
  end
end

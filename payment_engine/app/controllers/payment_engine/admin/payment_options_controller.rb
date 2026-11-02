# frozen_string_literal: true

module PaymentEngine
  module Admin
    class PaymentOptionsController < BaseController
      before_action :set_record, only: [:show, :edit, :update, :destroy]
      before_action :set_membership_types, only: [:new, :create, :edit, :update]

      def index
        @records = PaymentOption.includes(:membership_type).order(:position, :name)
        @records = @records.where(membership_type_id: params[:membership_type_id]) if params[:membership_type_id].present?
        @records = @records.where(mode: params[:mode]) if params[:mode].present?
        @records = @records.where(status: params[:status]) if params[:status].present?
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      def new
        @record = PaymentOption.new(status: "active", mode: "one_time", interval: "month", interval_count: 1, currency: "COP")
      end

      def create
        @record = PaymentOption.new(payment_option_params)
        if @record.save
          redirect_to admin_payment_option_path(@record), notice: "Creado correctamente."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @record.update(payment_option_params)
          redirect_to admin_payment_option_path(@record), notice: "Actualizado correctamente."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if Purchase.where(payment_option_id: @record.id).exists?
          redirect_to admin_payment_options_path, alert: "No se puede eliminar porque tiene historial."
        else
          @record.destroy
          redirect_to admin_payment_options_path, notice: "Eliminado."
        end
      end

      private

      def set_record
        @record = PaymentOption.find(params[:id])
      end

      def set_membership_types
        @membership_types = MembershipType.order(:name)
      end

      def payment_option_params
        params.require(:payment_option).permit(:membership_type_id, :name, :description, :price, :currency, :mode, :interval, :interval_count, :trial_days, :status, :position, :access_duration_count, :access_duration_unit)
      end
    end
  end
end

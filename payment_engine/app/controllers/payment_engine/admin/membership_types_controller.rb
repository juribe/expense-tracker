# frozen_string_literal: true

module PaymentEngine
  module Admin
    class MembershipTypesController < BaseController
      before_action :set_record, only: [:show, :edit, :update, :destroy, :archive]

      def index
        @records = MembershipType.order(:position, :name)
        @records = @records.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        @records = @records.page(params[:page]) if @records.respond_to?(:page)
      end

      def show; end

      def new
        @record = MembershipType.new(status: "active")
      end

      def create
        @record = MembershipType.new(membership_type_params)
        if @record.save
          redirect_to admin_membership_type_path(@record), notice: "Creado correctamente."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @record.update(membership_type_params)
          redirect_to admin_membership_type_path(@record), notice: "Actualizado correctamente."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @record.payment_options.any? || @record.memberships.any?
          redirect_to admin_membership_types_path, alert: "No se puede eliminar porque tiene historial."
        else
          @record.destroy
          redirect_to admin_membership_types_path, notice: "Eliminado."
        end
      end

      def archive
        @record.update!(status: "archived")
        redirect_to admin_membership_types_path, notice: "Archivado."
      end

      private

      def set_record
        @record = MembershipType.find(params[:id])
      end

      def membership_type_params
        params.require(:membership_type).permit(:name, :code, :description, :status, :position, metadata: {})
      end
    end
  end
end

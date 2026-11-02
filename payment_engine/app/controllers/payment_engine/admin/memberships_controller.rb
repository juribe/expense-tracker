# frozen_string_literal: true

module PaymentEngine
  module Admin
    class MembershipsController < BaseController
      before_action :set_record, only: [:show, :edit, :update, :destroy, :suspend, :reactivate, :extend]

      def index
        @records = Membership.includes(:membership_type, :owner).order(created_at: :desc)
        @records = @records.where(status: params[:status]) if params[:status].present?
        @records = @records.where(membership_type_id: params[:membership_type_id]) if params[:membership_type_id].present?
        @records = @records.where("owner_id = ?", params[:owner_id]) if params[:owner_id].present?
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      def new
        @record = Membership.new(status: "active", starts_at: Time.current)
        @membership_types = MembershipType.active.order(:name)
      end

      def create
        @record = Membership.new(membership_params)
        @membership_types = MembershipType.active.order(:name)
        owner = resolve_owner(params[:owner_type], params[:owner_id])
        @record.owner = owner if owner
        result = Memberships::Grant.call(
          owner: owner,
          membership_type: @record.membership_type,
          starts_at: @record.starts_at,
          expires_at: @record.expires_at,
          source: "manual",
          actor: current_host_user,
          reason: params[:reason]
        )
        if result.success?
          redirect_to admin_membership_path(result.record), notice: "Membresía concedida."
        else
          @record = Membership.new(membership_params)
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @membership_types = MembershipType.active.order(:name)
      end

      def update
        if @record.update(membership_params.except(:owner_type, :owner_id))
          redirect_to admin_membership_path(@record), notice: "Actualizado."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def suspend
        result = Memberships::Suspend.call(membership: @record, actor: current_host_user, reason: params[:reason])
        if result.success?
          redirect_to admin_membership_path(@record), notice: "Suspendida."
        else
          redirect_to admin_membership_path(@record), alert: result.errors.join(", ")
        end
      end

      def reactivate
        result = Memberships::Reactivate.call(membership: @record, actor: current_host_user, reason: params[:reason])
        if result.success?
          redirect_to admin_membership_path(@record), notice: "Reactivada."
        else
          redirect_to admin_membership_path(@record), alert: result.errors.join(", ")
        end
      end

      def extend
        new_date = params[:new_expires_at].present? ? Time.zone.parse(params[:new_expires_at]) : nil
        result = Memberships::Extend.call(membership: @record, new_expires_at: new_date, actor: current_host_user, reason: params[:reason])
        if result.success?
          redirect_to admin_membership_path(@record), notice: "Extendida."
        else
          redirect_to admin_membership_path(@record), alert: result.errors.join(", ")
        end
      end

      def destroy
        redirect_to admin_memberships_path, alert: "No permitido."
      end

      private

      def set_record
        @record = Membership.find(params[:id])
      end

      def membership_params
        params.require(:membership).permit(:membership_type_id, :status, :starts_at, :expires_at)
      end

      def resolve_owner(type, id)
        return nil if type.blank? || id.blank?
        type.constantize.find_by(id: id) rescue nil
      end
    end
  end
end

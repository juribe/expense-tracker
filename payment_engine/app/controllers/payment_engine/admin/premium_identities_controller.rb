# frozen_string_literal: true

module PaymentEngine
  module Admin
    # PremiumIdentitiesController
    # Admin listing and audited release of historical premium identities.
    # GET  /payment_engine/admin/premium_identities
    # GET  /payment_engine/admin/premium_identities/:id
    # POST /payment_engine/admin/premium_identities/:id/release
    class PremiumIdentitiesController < PaymentEngine::Admin::BaseController
      before_action :set_record, only: [ :show, :release ]

      def index
        @records = ::PremiumIdentity.includes(:first_user, :membership).order(first_used_at: :desc)
        @records = @records.where(identity_type: params[:identity_type]) if params[:identity_type].present?
        @records = filter_by_status(@records)
        @records = @records.paginate(page: params[:page], per_page: 25)
      end

      def show; end

      def release
        result = ::PremiumIdentities::Release.call(
          identity: @record,
          actor: current_host_user,
          reason: params[:reason]
        )

        if result.success?
          redirect_to admin_premium_identity_path(@record), notice: "Identidad liberada."
        else
          redirect_to admin_premium_identity_path(@record), alert: result.errors.join(", ")
        end
      end

      private

      def set_record
        @record = ::PremiumIdentity.find(params[:id])
      end

      def filter_by_status(records)
        case params[:status]
        when "active" then records.active
        when "released" then records.released
        else records
        end
      end
    end
  end
end

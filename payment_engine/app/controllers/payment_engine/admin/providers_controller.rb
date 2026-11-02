# frozen_string_literal: true

module PaymentEngine
  module Admin
    class ProvidersController < BaseController
      before_action :set_record, only: [:show, :edit, :update, :destroy, :test_connection]

      def index
        @records = Provider.order(:name)
      end

      def show; end

      def new
        @record = Provider.new(environment: "sandbox", active: false, credentials: {}, settings: {}, capabilities: {})
      end

      def create
        @record = Provider.new(provider_params)
        if @record.save
          redirect_to admin_provider_path(@record), notice: "Creado."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        # merge credentials: only update provided non-blank
        if @record.update(provider_params)
          redirect_to admin_provider_path(@record), notice: "Actualizado."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @record.destroy
        redirect_to admin_providers_path, notice: "Eliminado."
      end

      def test_connection
        # simple: mark last_activity
        @record.update!(last_activity_at: Time.current)
        redirect_to admin_provider_path(@record), notice: "Conexión probada (simulada)."
      end

      private

      def set_record
        @record = Provider.find(params[:id])
      end

      def provider_params
        raw = params.require(:provider)
        creds = parse_json_field(raw[:credentials])
        caps = parse_json_field(raw[:capabilities])
        settings = parse_json_field(raw[:settings])
        base = raw.permit(:code, :name, :environment, :active)
        base = base.merge(credentials: creds) if creds
        base = base.merge(capabilities: caps) if caps
        base = base.merge(settings: settings) if settings
        base
      end

      def parse_json_field(val)
        return nil if val.blank?
        if val.is_a?(String)
          JSON.parse(val) rescue nil
        else
          val.to_unsafe_h rescue val
        end
      end
    end
  end
end

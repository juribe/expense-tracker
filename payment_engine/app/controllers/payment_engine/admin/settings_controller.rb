# frozen_string_literal: true

module PaymentEngine
  module Admin
    class SettingsController < BaseController
      def show
        @setting = Setting.current
      end

      def update
        @setting = Setting.current
        if @setting.update(settings_params)
          redirect_to admin_settings_path, notice: "Configuración actualizada."
        else
          render :show, status: :unprocessable_entity
        end
      end

      def commercial
        @setting = Setting.current
      end

      def update_commercial
        @setting = Setting.current
        old = @setting.attributes.dup
        if @setting.update(commercial_params)
          record_audit(action: "settings.commercial_updated", auditable: @setting, reason: "commercial_config", changes: { before: old, after: @setting.attributes })
          redirect_to admin_commercial_settings_path, notice: "Configuración guardada."
        else
          render :commercial, status: :unprocessable_entity
        end
      end

      private

      def settings_params
        params.require(:setting).permit(:default_currency, :time_zone, :locale, :membership_policy, :expiration_policy, :grace_days, :cancellation_policy, :audit_enabled, :notification_email, :payments_enabled, :paid_access_required, :free_trial_enabled, :free_trial_duration_days, :free_trial_requires_card, :free_trial_once_per_user)
      end

      def commercial_params
        params.require(:setting).permit(:payments_enabled, :paid_access_required, :free_trial_enabled, :free_trial_duration_days, :free_trial_requires_card, :free_trial_once_per_user)
      end
    end
  end
end

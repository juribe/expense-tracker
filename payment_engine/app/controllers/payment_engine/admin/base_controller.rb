# frozen_string_literal: true

module PaymentEngine
  module Admin
    class BaseController < PaymentEngine::ApplicationController
      before_action :pe_require_authentication
      before_action :pe_require_authorization
      layout "payment_engine/admin"

      private

      def pe_require_authentication
        cfg = PaymentEngine.configuration
        cb = cfg.admin_authentication
        if cb.nil?
          return deny_access
        end
        begin
          cb.call(self)
        rescue
          return deny_access
        end
        return if response.redirect? || response.committed?
        deny_access unless current_host_user.present?
      end

      def pe_require_authorization
        cfg = PaymentEngine.configuration
        cb = cfg.admin_authorization
        if cb.nil?
          return deny_access
        end
        begin
          allowed = cb.call(self)
        rescue
          allowed = false
        end
        deny_access unless allowed
      end

      def deny_access
        if current_host_user.nil?
          begin
            redirect_to PaymentEngine.configuration.login_path.call(self), alert: "Debes iniciar sesión."
          rescue
            head :forbidden
          end
        else
          redirect_to main_app.dashboard_path,
                      alert: I18n.t("errors.not_authorized", default: "No tienes permiso para acceder a esta sección.")
        end
      rescue NoMethodError
        render "payment_engine/admin/forbidden", status: :forbidden, layout: "payment_engine/admin"
      end

      # Destructive admin actions must prove the acting admin's password, not
      # just an authenticated admin session.
      def pe_require_password_confirmation
        return if current_host_user&.valid_password?(params[:admin_password])

        redirect_back fallback_location: admin_root_path,
                      alert: "Confirma tu contraseña para continuar."
      end

      def audit_actor
        current_host_user
      end

      def record_audit(action:, auditable:, reason: nil, changes: {}, metadata: {})
        actor = audit_actor
        PaymentEngine::AuditLog.create!(
          actor_type: actor&.class&.name || PaymentEngine.configuration.audit_actor_type,
          actor_id: actor&.id,
          action: action,
          auditable_type: auditable&.class&.name,
          auditable_id: auditable&.id,
          reason: reason,
          changes: changes,
          metadata: metadata
        )
      rescue StandardError => e
        Rails.logger.warn("AuditLog failed: #{e.message}")
      end
    end
  end
end

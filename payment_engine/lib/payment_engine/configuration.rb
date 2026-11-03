module PaymentEngine
  class Configuration
    attr_accessor :admin_authentication, :admin_authorization, :current_user,
                  :login_path, :owner_resolver, :audit_actor_type,
                  :default_provider, :providers, :membership_timezone,
                  :expiration_grace_period_days, :revoke_access_on_refund,
                  :webhook_tolerance_seconds, :purchase_duplicate_window_minutes,
                  :logger

    def initialize
      @admin_authentication = nil
      @admin_authorization = nil
      @current_user = lambda { |controller| controller.respond_to?(:current_user) ? controller.current_user : nil }
      @login_path = lambda { |controller|
        if controller.main_app.respond_to?(:new_user_session_path)
          controller.main_app.new_user_session_path
        else
          controller.main_app.root_path
        end
      }
      @owner_resolver = lambda { |owner| PaymentEngine::Configuration.default_owner_resolver(owner) }
      @audit_actor_type = "User"

      @default_provider = nil
      @providers = {}
      @membership_timezone = "UTC"
      @expiration_grace_period_days = 0
      @revoke_access_on_refund = true
      @webhook_tolerance_seconds = 300
      @purchase_duplicate_window_minutes = 15
      @logger = nil
    end

    def provider_settings(name)
      (@providers || {}).fetch(name.to_sym, {}).to_h.symbolize_keys
    end

    def expiration_grace_period
      expiration_grace_period_days.to_i.days
    end

    def engine_logger
      @logger || (defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : Logger.new($stdout))
    end

    def self.settings
      PaymentEngine::Setting.current
    rescue
      nil
    end

    def self.payments_enabled?
      (settings&.payments_enabled != false)
    end

    def self.paid_access_required?
      (settings&.paid_access_required != false)
    end

    def self.free_trial_enabled?
      (settings&.free_trial_enabled != false)
    end

    def self.free_trial_duration_days
      settings&.free_trial_duration_days || 60
    end

    def self.free_trial_requires_card?
      settings&.free_trial_requires_card == true
    end

    def self.free_trial_once_per_user?
      settings&.free_trial_once_per_user != false
    end

    def self.default_owner_resolver(owner)
      return { label: "—", type: nil, id: nil } unless owner
      label = if owner.respond_to?(:name) && owner.name.present?
                owner.name
              elsif owner.respond_to?(:email) && owner.email.present?
                owner.email
              else
                "#{owner.class.name}##{owner.id}"
              end
      { label: label, type: owner.class.name, id: owner.id }
    end
  end

  module_function

  def configuration
    @configuration ||= Configuration.new
  end

  def configure
    yield configuration
    reset_providers!
    configuration
  end

  def reset_configuration!
    @configuration = Configuration.new
    reset_providers!
  end
end
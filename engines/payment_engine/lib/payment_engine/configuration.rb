module PaymentEngine
  # Central engine configuration. Provider credentials never live in the domain
  # models; they are read from the host application's environment or credentials.
  class Configuration
    DEFAULT_WEBHOOK_PATH = "/payment_engine/webhooks".freeze

    attr_accessor :default_provider,
                  :providers,
                  :membership_timezone,
                  :expiration_grace_period_days,
                  :revoke_access_on_refund,
                  :webhook_tolerance_seconds,
                  :purchase_duplicate_window_minutes,
                  :logger

    def initialize
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
      providers.fetch(name.to_sym, {}).to_h.symbolize_keys
    end

    def expiration_grace_period
      expiration_grace_period_days.to_i.days
    end

    def engine_logger
      logger || (defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : Logger.new($stdout))
    end
  end
end

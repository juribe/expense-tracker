require "active_support"
require "bigdecimal"
require "securerandom"
require "time"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/integer/time"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/time/calculations"

require "payment_engine/version"
require "payment_engine/result"
require "payment_engine/configuration"
require "payment_engine/events"
require "payment_engine/providers/base"
require "payment_engine/providers/registry"
require "payment_engine/providers/fake"
require "payment_engine/providers/epayco/client"
require "payment_engine/providers/epayco/webhook_handler"
require "payment_engine/providers/epayco"
require "payment_engine/engine"
require "payment_engine/access"
require "payment_engine/access_policy"

module PaymentEngine
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class UnknownProviderError < Error; end

  class << self
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

    def register_provider(name, klass)
      providers.register(name, klass)
      reset_providers!
      klass
    end

    def providers
      @providers ||= Providers::Registry.new
    end

    def provider(name = nil)
      key = resolve_provider_name(name)
      provider_instances[key] ||= providers.fetch(key).new(settings: provider_settings_for(key))
    end

    def provider_settings_for(key)
      settings = configuration.provider_settings(key)
      return settings if settings.present?

      # Allow credentials configured through the PaymentEngine admin UI to be
      # used by the adapters when no application-level configuration exists.
      begin
        # Normalize: admin-created providers may store the code in any case.
        record = PaymentEngine::Provider.where(Arel.sql("lower(code) = ?"), key.to_s.downcase).first
        return {} unless record

        record.credentials.to_h.merge(record.settings.to_h).symbolize_keys
      rescue StandardError
        {}
      end
    end

    def provider?(name)
      providers.registered?(name)
    end

    def reset_providers!
      @provider_instances = {}
    end

    def on(name, &block)
      Events.on(name, &block)
    end

    def current_time
      Time.current.in_time_zone(configuration.membership_timezone)
    rescue
      Time.current
    end

    private

    def provider_instances
      @provider_instances ||= {}
    end

    def resolve_provider_name(name)
      resolved = name || configuration.default_provider
      raise ConfigurationError, "No payment provider configured" if resolved.blank?

      resolved.to_sym
    end
  end
end

PaymentEngine.register_provider(:fake, PaymentEngine::Providers::Fake)
PaymentEngine.register_provider(:epayco, PaymentEngine::Providers::Epayco)
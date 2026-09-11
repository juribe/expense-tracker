# frozen_string_literal: true

module Ai
  # Client registry and tier factory. Each vendor is a Provider subclass that
  # knows its own endpoint, API-key conventions and defaults; the tier factory
  # instantiates the right client from the environment configuration, so
  # business logic never names a vendor.
  #
  #   AI_STRONG_PROVIDER=mistral  AI_STRONG_MODEL=mistral-small-latest
  #   AI_CHEAP_PROVIDER=flexai    AI_CHEAP_MODEL=Mistral-Nemo-Instruct-2407-FP8
  #
  #   Ai::Providers.strong  # => Ai::Providers::Mistral (strong model)
  #   Ai::Providers.cheap   # => Ai::Providers::FlexAi, or nil when the cheap
  #                          #    tier has no model configured
  module Providers
    TIER_STRONG = :strong
    TIER_CHEAP = :cheap

    CLIENTS = {} # provider name (String) => Provider subclass

    module_function

    # Registers a vendor client, e.g. Providers.register "mistral", Providers::Mistral
    def register(name, klass)
      CLIENTS[name.to_s] = klass
    end

    # Maps env provider names to client classes; referencing the constant
    # autoloads the file, which registers the client. Third-party clients can
    # simply call Providers.register before use.
    KNOWN_CLIENTS = {
      "mistral" => "Ai::Providers::Mistral",
      "flexai" => "Ai::Providers::FlexAi",
      "openrouter" => "Ai::Providers::OpenRouter"
    }.freeze

    # Instantiates a vendor client with per-tier overrides. Explicit
    # api_key/base_url arguments win over the client's own env conventions.
    def build(provider:, model:, api_key: nil, base_url: nil)
      KNOWN_CLIENTS[provider.to_s]&.constantize unless CLIENTS.key?(provider.to_s)
      klass = CLIENTS[provider.to_s]
      raise ArgumentError, "unknown AI provider client: #{provider.inspect} (registered: #{CLIENTS.keys.join(', ')})" if klass.nil?

      klass.new(model: model, api_key: api_key, base_url: base_url)
    end

    def for(tier)
      tier.to_sym == TIER_CHEAP ? cheap : strong
    end

    def strong(config: Ai.configuration)
      build(
        provider: config.strong_provider,
        model: config.strong_model,
        api_key: ENV["AI_STRONG_API_KEY"].presence,
        base_url: ENV["AI_STRONG_BASE_URL"].presence
      )
    end

    def cheap(config: Ai.configuration)
      return nil if config.cheap_model.blank?

      build(
        provider: config.cheap_provider,
        model: config.cheap_model,
        api_key: config.cheap_api_key,
        base_url: config.cheap_base_url
      )
    end
  end
end

# frozen_string_literal: true

module Ai
  # Builds the providers for each routing tier from the environment
  # configuration, so business logic never knows which vendor is behind a
  # tier. All current providers are OpenAI chat-completions compatible; adding
  # a non-compatible vendor only requires a new Provider subclass here.
  #
  #   Ai::Providers.for(:strong)  # => configured strong provider (may still be
  #                                #    unconfigured when no API key is set)
  #   Ai::Providers.for(:cheap)   # => cheap provider, or nil when the cheap
  #                                #    tier is disabled in the environment
  module Providers
    module_function

    TIER_STRONG = :strong
    TIER_CHEAP = :cheap

    def for(tier)
      tier.to_sym == TIER_CHEAP ? cheap : strong
    end

    def strong(config: Ai.configuration)
      Provider.new(
        name: config.strong_provider,
        model: config.strong_model,
        api_key: config.strong_api_key,
        base_url: config.strong_base_url
      )
    end

    def cheap(config: Ai.configuration)
      return nil unless config.cheap_enabled?

      Provider.new(
        name: config.cheap_provider,
        model: config.cheap_model,
        api_key: config.cheap_api_key,
        base_url: config.cheap_base_url
      )
    end
  end
end

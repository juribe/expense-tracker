# frozen_string_literal: true

module Ai
  # Central, environment-driven configuration for the AI tier architecture.
  # Values are read from ENV lazily on every access so tests (and deploy
  # changes) never require resetting memoized state.
  #
  # Vendor endpoints and API-key conventions live in the provider clients
  # (Ai::Providers::*); this class only carries tier selection and thresholds:
  #
  #   AI_STRONG_PROVIDER             client name for the strong tier (default: "mistral")
  #   AI_STRONG_MODEL                strong model (default: MISTRAL_MODEL or "mistral-small-latest")
  #   AI_CHEAP_PROVIDER              client name for the cheap tier ("mistral", "flexai", ...)
  #   AI_CHEAP_MODEL                 cheap-tier model; the cheap tier is disabled when unset
  #   AI_CHEAP_API_KEY               API key override (falls back to the client's own env)
  #   AI_CHEAP_BASE_URL              endpoint override (falls back to the client's default)
  #   AI_CHEAP_CONFIDENCE_THRESHOLD  minimum confidence to accept a cheap result
  #                                  without escalating to the strong tier (default: 0.90)
  #   AI_DETERMINISTIC_THRESHOLD     minimum confidence to accept a fully deterministic
  #                                  resolution without any AI call
  #                                  (default: AI_CHEAP_CONFIDENCE_THRESHOLD)
  #   AI_DISABLE_STRONG_TIER         when truthy (1/true/yes), no AI task reaches the
  #                                  strong tier: low-confidence cheap results are
  #                                  accepted as-is instead of escalating
  class Configuration
    DEFAULT_STRONG_PROVIDER = "mistral"
    DEFAULT_STRONG_MODEL = "mistral-small-latest"
    DEFAULT_CHEAP_CONFIDENCE_THRESHOLD = 0.90

    def strong_provider
      ENV["AI_STRONG_PROVIDER"].presence || DEFAULT_STRONG_PROVIDER
    end

    def strong_model
      ENV["AI_STRONG_MODEL"].presence || ENV["MISTRAL_MODEL"].presence || DEFAULT_STRONG_MODEL
    end

    # Vision-capable model on the strong tier, used for receipt/image input.
    # The old default (pixtral-12b-24091063) was retired by Mistral; the
    # strong default is vision-capable and keeps one model in play.
    def vision_model
      ENV["MISTRAL_VISION_MODEL"].presence || ENV["AI_VISION_MODEL"].presence || DEFAULT_STRONG_MODEL
    end

    def cheap_provider
      ENV["AI_CHEAP_PROVIDER"].presence
    end

    def cheap_model
      ENV["AI_CHEAP_MODEL"].presence
    end

    def cheap_api_key
      ENV["AI_CHEAP_API_KEY"].presence
    end

    def cheap_base_url
      ENV["AI_CHEAP_BASE_URL"].presence
    end

    # The cheap tier only runs when a model is set and the client it resolves
    # to is properly configured (key + endpoint come from the client defaults
    # or the explicit overrides above).
    def cheap_enabled?
      provider = cheap_provider
      return false if cheap_model.blank? || provider.blank?

      client = Providers.build(provider: provider, model: cheap_model,
                               api_key: cheap_api_key, base_url: cheap_base_url)
      client.configured?
    rescue ArgumentError
      false
    end

    # Whether any AI tier is usable: the strong tier via the default Mistral
    # client (direct env key) or the cheap tier (model + client configured).
    def configured?
      ENV["MISTRAL_API_KEY"].present? || cheap_enabled?
    end

    def cheap_confidence_threshold
      Float(ENV["AI_CHEAP_CONFIDENCE_THRESHOLD"].presence || DEFAULT_CHEAP_CONFIDENCE_THRESHOLD)
    rescue ArgumentError, TypeError
      DEFAULT_CHEAP_CONFIDENCE_THRESHOLD
    end

    def deterministic_threshold
      Float(ENV["AI_DETERMINISTIC_THRESHOLD"].presence || cheap_confidence_threshold)
    rescue ArgumentError, TypeError
      cheap_confidence_threshold
    end

    # Cost guard: with the strong tier switched off, cheap results are the
    # ceiling for every task — low-confidence ones are accepted rather than
    # escalated, and tasks without a cheap tier fail cleanly.
    def strong_tier_disabled?
      %w[1 true yes].include?(ENV["AI_DISABLE_STRONG_TIER"].to_s.downcase.strip)
    end
  end
end

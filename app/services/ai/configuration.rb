# frozen_string_literal: true

module Ai
  # Central, environment-driven configuration for the AI tier architecture.
  # Values are read from ENV lazily on every access so tests (and deploy
  # changes) never require resetting memoized state.
  #
  #   AI_STRONG_PROVIDER             provider name for the strong tier (default: "mistral")
  #   AI_STRONG_MODEL                strong model (default: MISTRAL_MODEL or "mistral-small-latest")
  #   AI_CHEAP_PROVIDER              provider name for the cheap tier; cheap tier is
  #                                  disabled when unset
  #   AI_CHEAP_MODEL                 cheap/strong-cheap model (e.g. "ministral-3b-latest")
  #   AI_CHEAP_BASE_URL              chat-completions endpoint for the cheap tier
  #   AI_CHEAP_API_KEY               API key for the cheap tier (falls back to the
  #                                  strong key when the provider is "mistral")
  #   AI_CHEAP_CONFIDENCE_THRESHOLD  minimum confidence required to accept a cheap
  #                                  tier result without escalating (default: 0.90)
  #   AI_DETERMINISTIC_THRESHOLD     minimum confidence required to accept a fully
  #                                  deterministic resolution without any AI call
  #                                  (default: AI_CHEAP_CONFIDENCE_THRESHOLD)
  class Configuration
    DEFAULT_STRONG_MODEL = "mistral-small-latest"
    DEFAULT_STRONG_PROVIDER = "mistral"
    MISTRAL_DEFAULT_BASE_URL = "https://api.mistral.ai/v1/chat/completions"
    DEFAULT_CHEAP_CONFIDENCE_THRESHOLD = 0.90

    def strong_provider
      ENV["AI_STRONG_PROVIDER"].presence || DEFAULT_STRONG_PROVIDER
    end

    def strong_model
      ENV["AI_STRONG_MODEL"].presence || ENV["MISTRAL_MODEL"].presence || DEFAULT_STRONG_MODEL
    end

    def strong_api_key
      ENV["MISTRAL_API_KEY"].presence
    end

    def strong_base_url
      ENV["MISTRAL_BASE_URL"].presence || MISTRAL_DEFAULT_BASE_URL
    end

    # Vision-capable model on the strong tier, used for receipt/image input.
    def vision_model
      ENV["MISTRAL_VISION_MODEL"].presence || ENV["AI_VISION_MODEL"].presence || "pixtral-12b-24091063"
    end

    def cheap_provider
      ENV["AI_CHEAP_PROVIDER"].presence
    end

    def cheap_model
      ENV["AI_CHEAP_MODEL"].presence
    end

    def cheap_base_url
      ENV["AI_CHEAP_BASE_URL"].presence ||
        (cheap_provider == "mistral" ? MISTRAL_DEFAULT_BASE_URL : nil)
    end

    def cheap_api_key
      ENV["AI_CHEAP_API_KEY"].presence ||
        (cheap_provider == "mistral" ? strong_api_key : nil)
    end

    # The cheap tier only runs when explicitly configured with a model, an
    # endpoint and a key; otherwise every task goes straight to the strong tier.
    def cheap_enabled?
      cheap_model.present? && cheap_base_url.present? && cheap_api_key.present?
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
  end
end

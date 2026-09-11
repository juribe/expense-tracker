# frozen_string_literal: true

module Ai
  module Providers
    # Mistral chat-completions client. The strong tier defaults to this
    # vendor; can serve both tiers (e.g. strong=mistral-small-latest,
    # cheap=ministral-3b-latest).
    #
    # Conventions:
    #   MISTRAL_API_KEY    API key
    #   MISTRAL_BASE_URL   endpoint override (default https://api.mistral.ai/v1/chat/completions)
    #   MISTRAL_MODEL      model fallback when AI_STRONG_MODEL/AI_CHEAP_MODEL unset
    class Mistral < Ai::Provider
      DEFAULT_BASE_URL = "https://api.mistral.ai/v1/chat/completions"

      def initialize(model:, api_key: nil, base_url: nil)
        super(
          name: "mistral",
          model: model.presence || ENV["MISTRAL_MODEL"].presence || Ai::Configuration::DEFAULT_STRONG_MODEL,
          api_key: api_key.presence || ENV["MISTRAL_API_KEY"].presence,
          base_url: base_url.presence || ENV["MISTRAL_BASE_URL"].presence || DEFAULT_BASE_URL
        )
      end
    end

    register "mistral", Mistral
  end
end

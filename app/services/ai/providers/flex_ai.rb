# frozen_string_literal: true

module Ai
  module Providers
    # Flex AI chat-completions client (OpenAI-compatible endpoint), used as a
    # low-cost tier for simple structured tasks.
    #
    # Conventions:
    #   FLEX_API_KEY    API key (AI_CHEAP_API_KEY is also honored)
    #   FLEX_BASE_URL   endpoint override (default https://api.flex.ai/v1/chat/completions)
    class FlexAi < Ai::Provider
      DEFAULT_BASE_URL = "https://api.flex.ai/v1/chat/completions"

      def initialize(model:, api_key: nil, base_url: nil)
        super(
          name: "flexai",
          model: model,
          api_key: api_key.presence || ENV["FLEX_API_KEY"].presence || ENV["AI_CHEAP_API_KEY"].presence,
          base_url: base_url.presence || ENV["FLEX_BASE_URL"].presence || DEFAULT_BASE_URL
        )
      end
    end

    register "flexai", FlexAi
  end
end

# frozen_string_literal: true

module Ai
  module Providers
    # OpenRouter chat-completions client (OpenAI-compatible gateway to many
    # hosted models, e.g. "mistralai/mistral-nemo").
    #
    # Conventions:
    #   OPENROUTER_API_KEY     API key (AI_CHEAP_API_KEY is also honored)
    #   OPENROUTER_BASE_URL    endpoint override (default https://openrouter.ai/api/v1/chat/completions)
    #   OPENROUTER_SITE_URL    attribution header (HTTP-Referer), optional
    #   OPENROUTER_APP_NAME    attribution header (X-OpenRouter-Title), optional
    class OpenRouter < Ai::Provider
      DEFAULT_BASE_URL = "https://openrouter.ai/api/v1/chat/completions"

      def initialize(model:, api_key: nil, base_url: nil)
        super(
          name: "openrouter",
          model: model,
          api_key: api_key.presence || ENV["OPENROUTER_API_KEY"].presence || ENV["AI_CHEAP_API_KEY"].presence,
          base_url: base_url.presence || ENV["OPENROUTER_BASE_URL"].presence || DEFAULT_BASE_URL
        )
      end

      private

      def extra_headers
        headers = {}
        site_url = ENV["OPENROUTER_SITE_URL"].presence
        app_name = ENV["OPENROUTER_APP_NAME"].presence
        headers["HTTP-Referer"] = site_url if site_url
        headers["X-OpenRouter-Title"] = app_name if app_name
        headers
      end
    end

    register "openrouter", OpenRouter
  end
end

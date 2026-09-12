# frozen_string_literal: true

module Ai
  # Configurable model pricing for cost estimation. Prices are USD per 1M
  # tokens and come from ENV so the evaluation engine never hard-codes vendor
  # rates; optional per-model overrides are provided as a JSON map keyed by
  # "provider/model":
  #
  #   AI_PRICE_INPUT_PER_MILLION      0.15
  #   AI_PRICE_OUTPUT_PER_MILLION     0.60
  #   AI_MODEL_PRICES_JSON            {"openrouter/upstage/solar-pro4":{"input":0.2,"output":0.8}}
  module Pricing
    DEFAULT_INPUT_PER_MILLION = 0.0
    DEFAULT_OUTPUT_PER_MILLION = 0.0

    module_function

    def cost(input_tokens:, output_tokens:, provider: nil, model: nil)
      input = input_tokens.to_i
      output = output_tokens.to_i
      price = per_million(provider: provider, model: model)
      ((input / 1_000_000.0) * price[:input]) + ((output / 1_000_000.0) * price[:output])
    end

    # Same as #cost but returns the input/output parts separately (USD).
    def split_cost(input_tokens:, output_tokens:, provider: nil, model: nil)
      input = input_tokens.to_i
      output = output_tokens.to_i
      price = per_million(provider: provider, model: model)
      {
        input: ((input / 1_000_000.0) * price[:input]).round(8),
        output: ((output / 1_000_000.0) * price[:output]).round(8)
      }
    end

    def per_million(provider: nil, model: nil)
      overrides[price_key(provider, model)] || {
        input: configured("AI_PRICE_INPUT_PER_MILLION", DEFAULT_INPUT_PER_MILLION),
        output: configured("AI_PRICE_OUTPUT_PER_MILLION", DEFAULT_OUTPUT_PER_MILLION)
      }
    end

    def configured(key, default)
      value = ENV[key].presence
      value ? Float(value) : default
    rescue ArgumentError, TypeError
      default
    end

    def price_key(provider, model)
      return nil if provider.blank? || model.blank?

      "#{provider}/#{model}"
    end

    def overrides
      raw = ENV["AI_MODEL_PRICES_JSON"].presence
      return {} if raw.nil?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end

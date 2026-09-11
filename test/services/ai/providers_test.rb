# frozen_string_literal: true

require "test_helper"

module Ai
  class ProvidersTest < ActiveSupport::TestCase
    test "builds the mistral client with its vendor defaults" do
      with_env({ "MISTRAL_API_KEY" => "mk", "MISTRAL_BASE_URL" => nil, "AI_STRONG_API_KEY" => nil,
                 "AI_STRONG_BASE_URL" => nil }) do
        client = Ai::Providers.build(provider: "mistral", model: "mistral-small-latest")

        assert_instance_of Ai::Providers::Mistral, client
        assert_equal "mistral", client.name
        assert_equal "mistral-small-latest", client.model
        assert client.configured?
      end
    end

    test "builds the flexai client with its vendor endpoint and key conventions" do
      with_env({ "FLEX_API_KEY" => "fk", "AI_CHEAP_API_KEY" => nil }) do
        client = Ai::Providers.build(provider: "flexai", model: "Mistral-Nemo-Instruct-2407-FP8")

        assert_instance_of Ai::Providers::FlexAi, client
        assert_equal "flexai", client.name
        assert_equal "Mistral-Nemo-Instruct-2407-FP8", client.model
        assert client.configured?
      end
    end

    test "flexai also accepts the tier-level AI_CHEAP_API_KEY" do
      with_env({ "FLEX_API_KEY" => nil, "AI_CHEAP_API_KEY" => "ck" }) do
        client = Ai::Providers.build(provider: "flexai", model: "some-model")
        assert client.configured?
      end
    end

    test "builds the openrouter client with its gateway endpoint, key and attribution headers" do
      env = { "OPENROUTER_API_KEY" => "ork", "AI_CHEAP_API_KEY" => nil, "OPENROUTER_BASE_URL" => nil,
              "OPENROUTER_SITE_URL" => "https://myapp.example", "OPENROUTER_APP_NAME" => "ExpenseTracker" }
      with_env(env) do
        client = Ai::Providers.build(provider: "openrouter", model: "mistralai/mistral-nemo")

        assert_instance_of Ai::Providers::OpenRouter, client
        assert_equal "openrouter", client.name
        assert_equal "mistralai/mistral-nemo", client.model
        assert client.configured?
        assert_equal({ "HTTP-Referer" => "https://myapp.example",
                       "X-OpenRouter-Title" => "ExpenseTracker" }, client.send(:extra_headers))
      end
    end

    test "openrouter client omits attribution headers when not configured" do
      with_env({ "OPENROUTER_API_KEY" => "ork", "OPENROUTER_SITE_URL" => nil, "OPENROUTER_APP_NAME" => nil }) do
        client = Ai::Providers.build(provider: "openrouter", model: "any-model")
        assert_equal({}, client.send(:extra_headers))
      end
    end

    test "raises a clear error for unknown provider names" do
      error = assert_raises(ArgumentError) do
        Ai::Providers.build(provider: "nope", model: "x")
      end
      assert_match(/unknown AI provider client/, error.message)
    end

    test "cheap returns nil when no cheap model is configured" do
      with_env({ "AI_CHEAP_MODEL" => nil }) do
        assert_nil Ai::Providers.cheap
      end
    end

    test "cheap instantiates the client selected by AI_CHEAP_PROVIDER" do
      env = { "AI_CHEAP_PROVIDER" => "flexai", "AI_CHEAP_MODEL" => "cheap-model",
              "AI_CHEAP_API_KEY" => "ck", "AI_CHEAP_BASE_URL" => nil, "FLEX_API_KEY" => nil }
      with_env(env) do
        client = Ai::Providers.cheap
        assert_instance_of Ai::Providers::FlexAi, client
        assert_equal "cheap-model", client.model
        assert client.configured?
      end
    end

    test "strong instantiates the client selected by AI_STRONG_PROVIDER" do
      env = { "AI_STRONG_PROVIDER" => "mistral", "AI_STRONG_MODEL" => "mistral-small-latest",
              "MISTRAL_API_KEY" => "mk" }
      with_env(env) do
        client = Ai::Providers.strong
        assert_instance_of Ai::Providers::Mistral, client
        assert_equal "mistral-small-latest", client.model
      end
    end

    test "cheap_enabled? reflects client configuration" do
      with_env({ "AI_CHEAP_PROVIDER" => "flexai", "AI_CHEAP_MODEL" => "m",
                 "AI_CHEAP_API_KEY" => "ck", "FLEX_API_KEY" => nil }) do
        assert Ai.configuration.cheap_enabled?
      end

      with_env({ "AI_CHEAP_PROVIDER" => "flexai", "AI_CHEAP_MODEL" => "m",
                 "AI_CHEAP_API_KEY" => nil, "FLEX_API_KEY" => nil }) do
        refute Ai.configuration.cheap_enabled?
      end

      with_env({ "AI_CHEAP_PROVIDER" => "unknown-vendor", "AI_CHEAP_MODEL" => "m" }) do
        refute Ai.configuration.cheap_enabled?
      end
    end
  end
end

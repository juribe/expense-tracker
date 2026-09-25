# frozen_string_literal: true

require "test_helper"

class Ai::ConfigurationTest < ActiveSupport::TestCase
  test "strong tier is enabled by default" do
    with_env({}) do
      refute Ai.configuration.strong_tier_disabled?
    end
  end

  test "strong tier switch accepts common truthy values" do
    [ "true", "1", "YES", "yes" ].each do |value|
      with_env({ "AI_DISABLE_STRONG_TIER" => value }) do
        assert Ai.configuration.strong_tier_disabled?, value
      end
    end
  end

  test "strong tier switch ignores falsy values" do
    [ "false", "0", "no", "" ].each do |value|
      with_env({ "AI_DISABLE_STRONG_TIER" => value }) do
        refute Ai.configuration.strong_tier_disabled?, value
      end
    end
  end
end

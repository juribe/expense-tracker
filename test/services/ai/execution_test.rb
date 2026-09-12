# frozen_string_literal: true

require "test_helper"

class AiExecutionTest < ActiveSupport::TestCase
  test "an execution with provider and model is an override" do
    execution = Ai::Execution.new(provider: "openrouter", model: "upstage/solar-pro4")
    assert execution.override?
    assert execution.force_ai?
  end

  test "blank provider or model does not force AI" do
    assert_not Ai::Execution.new.override?
    assert_not Ai::Execution.new.force_ai?
    assert_not Ai::Execution.new(provider: "mistral", model: "").override?
  end

  test "force_ai can be requested explicitly without an override" do
    execution = Ai::Execution.new(force_ai: true)
    assert_not execution.override?
    assert execution.force_ai?
  end
end
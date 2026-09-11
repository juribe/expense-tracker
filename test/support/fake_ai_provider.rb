# frozen_string_literal: true

# Test double for Ai::Provider. Feed it a queue of responses:
#
#   provider = FakeAiProvider.new(responses: [
#     '{"expenses": [{"amount": 1}]}',                       # raw JSON content
#     { content: "{}", input_tokens: 10, output_tokens: 5 }, # with usage data
#     Ai::Provider::Error.new("boom")                        # a raised failure
#   ])
#
# `provider.calls` records every messages payload it received.
class FakeAiProvider
  attr_reader :name, :model, :calls

  def initialize(name: "fake", model: "fake-model", responses: [])
    @name = name
    @model = model
    @responses = responses
    @calls = []
  end

  def configured?
    true
  end

  def chat(messages:, **_options)
    @calls << messages
    outcome = @responses.shift
    raise "no stubbed response left" if outcome.nil?

    case outcome
    when Ai::Provider::Error
      raise outcome
    when Hash
      Ai::Provider::Response.new(
        content: outcome[:content],
        model: outcome[:model] || @model,
        input_tokens: outcome[:input_tokens] || 0,
        output_tokens: outcome[:output_tokens] || 0
      )
    else
      Ai::Provider::Response.new(content: outcome.to_s, model: @model,
                                 input_tokens: 0, output_tokens: 0)
    end
  end
end

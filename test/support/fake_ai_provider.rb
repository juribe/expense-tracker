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
  attr_reader :name, :model, :calls, :responses

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

  # Streaming double: yields the content in small delta pieces, records the
  # messages payload in `calls`, and returns the full content as a Response.
  # A queued Ai::Provider::Error still raises.
  def chat_stream(messages:, **_options)
    @calls << messages
    outcome = @responses.shift
    raise "no stubbed response left" if outcome.nil?
    raise outcome if outcome.is_a?(Ai::Provider::Error)

    content = outcome.is_a?(Hash) ? outcome[:content].to_s : outcome.to_s
    content.scan(/.{1,10}/m).each { |delta| yield delta }

    Ai::Provider::Response.new(
      content: content,
      model: outcome.is_a?(Hash) && outcome[:model] ? outcome[:model] : @model,
      input_tokens: outcome.is_a?(Hash) ? outcome[:input_tokens].to_i : 0,
      output_tokens: outcome.is_a?(Hash) ? outcome[:output_tokens].to_i : 0
    )
  end
end

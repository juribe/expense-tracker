# frozen_string_literal: true

require "test_helper"

# The SpeechToText boundary is provider-independent: callers never depend on
# faster-whisper, and adding a provider must not touch the pipeline. Tests
# NEVER execute Whisper — the provider is stubbed at the boundary.
class SpeechToTextTest < ActiveSupport::TestCase
  test "selects the whisper provider by default" do
    assert_equal "whisper", SpeechToText.provider_name
    assert_equal SpeechToText::Whisper, SpeechToText.provider_class
  end

  test "provider selection is driven by SPEECH_TO_TEXT_PROVIDER" do
    with_env("SPEECH_TO_TEXT_PROVIDER" => "whisper") do
      assert_equal SpeechToText::Whisper, SpeechToText.provider_class
    end
  end

  test "an unknown provider raises a friendly application-level error" do
    with_env("SPEECH_TO_TEXT_PROVIDER" => "openai") do
      error = assert_raises(SpeechToText::ProviderUnavailableError) { SpeechToText.provider_class }
      assert_match(/openai/, error.message)
    end
  end

  test "transcribe delegates to the configured provider and returns its result" do
    audio = "data:audio/ogg;base64,#{Base64.strict_encode64('OGG')}"
    result = SpeechToText::Result.new(text: "Este es un ejemplo.", language: "es",
                                      provider: "whisper", model: "small")
    seen = {}

    stub_method(SpeechToText::Whisper, :call, ->(**kwargs) {
      seen.merge!(kwargs)
      result
    }) do
      returned = SpeechToText.transcribe(audio_data: audio, filename: "note.ogg")
      assert_equal audio, seen[:audio_data]
      assert_equal "note.ogg", seen[:filename]
      assert_equal "Este es un ejemplo.", returned.text
      assert_equal "whisper", returned.provider
    end
  end

  test "new providers can be registered without touching the pipeline" do
    stub_method(SpeechToText, :providers,
      { "whisper" => "SpeechToText::Whisper", "other" => "SpeechToText::FutureTestProvider" }) do
      with_env("SPEECH_TO_TEXT_PROVIDER" => "other") do
        stub_method(SpeechToText::FutureTestProvider, :call,
          SpeechToText::Result.new(text: "from future provider", provider: "other")) do
          assert_equal "from future provider", SpeechToText.transcribe(audio_data: "x", filename: nil).text
        end
      end
    end
  end
end

class SpeechToText::FutureTestProvider
  def self.call(**_kwargs)
    raise NotImplementedError
  end
end

# frozen_string_literal: true

require "open3"
require "tempfile"
require "timeout"

module SpeechToText
  # Provider-independent Speech-to-Text boundary. Audio becomes text here and
  # then flows through the SAME expense extraction pipeline used for typed
  # text — audio is just another way of producing text.
  #
  #   result = SpeechToText.transcribe(audio_data: "data:audio/ogg;base64,...", filename: "note.ogg")
  #   result.text      # => "Me gasté 50 mil en almuerzo"
  #   result.provider  # => "whisper"
  #   result.model     # => "small"
  #
  # The provider is selected through configuration (SPEECH_TO_TEXT_PROVIDER,
  # default "whisper"), so adding SpeechToText::OpenAI later requires no
  # changes in the pipeline, the Playground, or the models.
  class Error < StandardError; end

  # The audio format is not one of the supported ones.
  class UnsupportedFormatError < Error; end

  # FFmpeg preprocessing (16 kHz mono normalized WAV) failed.
  class PreprocessingError < Error; end

  # The provider could not produce a transcript (missing binary/model,
  # crashed process, timeout, unreadable audio, ...).
  class TranscriptionError < Error; end

  # No provider is registered for the configured name.
  class ProviderUnavailableError < Error; end

  class << self
    def transcribe(audio_data:, filename: nil)
      provider_class.call(audio_data: audio_data, filename: filename)
    end

    # Provider registry. Names map to class names (strings) so adding a
    # provider is a one-line registration without loading every provider.
    def provider_class
      class_name = providers[provider_name]
      raise ProviderUnavailableError,
            "Unknown speech-to-text provider: #{provider_name.inspect} (available: #{providers.keys.join(", ")})" if class_name.nil?

      class_name.constantize
    end

    def provider_name
      ENV.fetch("SPEECH_TO_TEXT_PROVIDER", "whisper")
    end

    def providers
      { "whisper" => "SpeechToText::Whisper" }
    end
  end
end

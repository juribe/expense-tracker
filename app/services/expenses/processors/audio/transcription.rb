# frozen_string_literal: true

class Expenses::Processors::Audio
  # The "speech-to-text way" of the Audio processor, as one step: transcribes
  # the voice note LOCALLY (provider from configuration, Whisper by default;
  # the audio never leaves the machine), records the :stt step and turns
  # failures into friendly pipeline errors — they never abort with a provider
  # stack trace. There is no separate audio extraction path afterwards: the
  # transcript is parsed through the same Text processor used for typed text.
  class Transcription
    Result = Struct.new(:ok?, :text, keyword_init: true)

    def self.call(input:, recording: nil)
      new(input: input, recording: recording).call
    end

    def initialize(input:, recording: nil)
      @input = input
      @recording = recording
    end

    def call
      result = SpeechToText.transcribe(audio_data: @input.audio_data, filename: @input.filename)
      @recording&.add_step(:stt, {
        applicable: true,
        provider: result.provider,
        model: result.model,
        language: result.language,
        language_probability: result.language_probability,
        duration: result.duration,
        text: result.text
      })

      if result.empty_transcript?
        @recording&.add_errors([ "Speech-to-text produced an empty transcript. The audio may be silent or too short." ])
        return Result.new(ok?: false, text: nil)
      end

      Result.new(ok?: true, text: result.text)
    rescue SpeechToText::Error => e
      @recording&.add_step(:stt, { applicable: true, provider: SpeechToText.provider_name, error: e.message })
      @recording&.add_errors([ e.message ])
      Result.new(ok?: false, text: nil)
    end
  end
end

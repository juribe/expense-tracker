# frozen_string_literal: true

module ExpenseProcessing
  module Processors
    # Audio channel processor. A voice note is just another way of producing
    # text: speech-to-text runs locally, and the transcript is parsed through
    # the same Text processor used for typed text (the user's optional note
    # carries explicit intent such as "pagado con nequi"). There is no
    # separate audio extraction path.
    class Audio < Base
      VOICE_CONTEXT = "This text was transcribed from a voice note by local speech-to-text. " \
                      "Extract the expense exactly as spoken."

      # Returns [candidate, engine]; candidate is nil when transcription or
      # extraction failed.
      def call
        transcript = run_speech_to_text
        if transcript.blank?
          @errors << "Could not extract an expense because no transcript was generated." if @errors.empty?
          return [ nil, nil ]
        end

        text_processor.call(
          [ note, transcript ].reject(&:blank?).join("\n"),
          context: VOICE_CONTEXT
        )
      end

      private

      # Speech-to-Text runs LOCALLY (provider from configuration, Whisper by
      # default) and the audio never leaves the machine. Failures become
      # friendly pipeline errors; they never abort with a provider stack trace.
      def run_speech_to_text
        result = SpeechToText.transcribe(audio_data: @input.audio_data, filename: @input.filename)
        @steps[:stt] = {
          applicable: true,
          provider: result.provider,
          model: result.model,
          language: result.language,
          language_probability: result.language_probability,
          duration: result.duration,
          text: result.text
        }
        if result.empty_transcript?
          @errors << "Speech-to-text produced an empty transcript. The audio may be silent or too short."
          return nil
        end
        result.text
      rescue SpeechToText::Error => e
        @steps[:stt] = { applicable: true, provider: SpeechToText.provider_name, error: e.message }
        @errors << e.message
        nil
      end
    end
  end
end

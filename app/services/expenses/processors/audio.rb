# frozen_string_literal: true

module Expenses
  module Processors
    # Audio channel processor. A voice note is just another way of producing
    # text: Transcription (local speech-to-text) produces the transcript, and
    # it is parsed through the same Text processor used for typed text (the
    # user's optional note carries explicit intent such as "pagado con
    # nequi"). There is no separate audio extraction path.
    class Audio < Base
      VOICE_CONTEXT = "This text was transcribed from a voice note by local speech-to-text. " \
                      "Extract the expense exactly as spoken."

      # Returns [candidate, engine]; candidate is nil when transcription or
      # extraction failed.
      def call
        transcription = Transcription.call(input: @input, recording: @recording)
        return [ nil, nil ] unless transcription.ok?

        text_processor.call(
          combined_text(transcription.text),
          context: VOICE_CONTEXT
        )
      end
    end
  end
end

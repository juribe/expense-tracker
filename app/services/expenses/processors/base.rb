# frozen_string_literal: true

module Expenses
  module Processors
    # Shared state for every channel processor. Processors compose: Audio does
    # speech-to-text then delegates to Text, Image does OCR then delegates to
    # Text, so they must all write into the SAME steps/errors/warnings
    # accumulated by the orchestrator.
    class Base
      def initialize(user:, input:, recording: nil)
        @user = user
        @input = input
        @recording = recording
      end

      # The user's optional note (explicit intent such as "pagado con nequi").
      # Not every channel carries it (image-only inputs have none).
      def note
        @input.payload[:text]
      end

      # Channels that produce their own text (transcript, OCR) combine it with
      # the user's note before parsing; the note carries explicit intent and
      # is skipped when blank.
      def combined_text(channel_text)
        [ note, channel_text ].reject(&:blank?).join("\n")
      end

      private

      def text_processor
        Text.new(user: @user, input: @input, recording: @recording)
      end
    end
  end
end

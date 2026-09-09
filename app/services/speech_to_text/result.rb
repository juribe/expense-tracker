# frozen_string_literal: true

module SpeechToText
  # Standardized transcription result. Every provider returns this structure,
  # so callers (the expense pipeline) never depend on the provider behind it.
  #
  #   result.text                  # => "Este es un ejemplo."
  #   result.language              # => "es"
  #   result.language_probability  # => 0.98
  #   result.duration              # => 5.2 (seconds of spoken audio)
  #   result.provider              # => "whisper"
  #   result.model                 # => "small"
  #   result.metadata              # => provider-specific extra info (Hash)
  Result = Struct.new(
    :text, :language, :language_probability, :duration, :provider, :model, :metadata,
    keyword_init: true
  ) do
    def initialize(*)
      super
      self.metadata ||= {}
      self.text = text.to_s.strip
    end

    # A transcript with no words is not usable for expense extraction; callers
    # treat it as a distinct, friendly failure instead of sending it to the
    # extractor.
    def empty_transcript?
      text.blank?
    end

    def to_h
      {
        text: text,
        language: language,
        language_probability: language_probability,
        duration: duration,
        provider: provider,
        model: model,
        metadata: metadata
      }
    end
  end
end

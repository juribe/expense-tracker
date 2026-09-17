# frozen_string_literal: true

module Expenses
  module Inputs
    # Audio channel. The transcript travels in `text` after speech-to-text;
    # the original filename is kept in metadata for diagnostics. The class
    # un-structures its payload into text + audio_data readers and owns the
    # audio information methods (extension/mime_type/base64) and its
    # validation rules.
    class Audio < Base
      extend Rules::Audio

      TYPE = "audio"
      PAYLOAD_KEYS = %i[text audio_data].freeze
      META_KEYS = %i[filename].freeze
      REQUIRED_FIELDS = { audio_data: "audio" }.freeze

      AUDIO_MIME_EXTENSIONS = {
        "audio/ogg" => "ogg", "application/ogg" => "ogg", "audio/opus" => "opus",
        "audio/mp4" => "m4a", "audio/x-m4a" => "m4a", "audio/mpeg" => "mp3",
        "audio/mp3" => "mp3", "audio/wav" => "wav", "audio/x-wav" => "wav",
        "audio/wave" => "wav", "audio/webm" => "webm"
      }.freeze

      def text
        payload[:text]
      end

      def audio_data
        payload[:audio_data]
      end

      def self.mime_type(audio_data)
        DataUri.mime_type(audio_data)
      end

      def self.base64(audio_data)
        DataUri.base64(audio_data)
      end

      # Extension from the data-URI mime type, falling back to the uploaded
      # filename (browsers often leave the audio mime type empty).
      def self.extension(audio_data, filename)
        AUDIO_MIME_EXTENSIONS[mime_type(audio_data).to_s] || DataUri.extension_from_filename(filename)
      end

      def self.channel_errors(input)
        audio_errors(input)
      end
    end
  end
end

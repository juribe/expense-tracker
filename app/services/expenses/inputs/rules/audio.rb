# frozen_string_literal: true

module Expenses
  module Inputs
    module Rules
      # Audio payload rules. Extended by the audio typed input; format info
      # (extension/base64) is read through the extended singleton.
      module Audio
        SUPPORTED_EXTENSIONS = %w[ogg opus m4a mp3 wav webm].freeze
        AUDIO_MAX_BYTES = 15.megabytes

        def audio_errors(input)
          errors = []
          if extension(input.audio_data, input.filename).in?(SUPPORTED_EXTENSIONS)
            errors << "Audio is too large (max #{AUDIO_MAX_BYTES / 1.megabyte} MB)." if decoded_audio_size(input) > AUDIO_MAX_BYTES
          else
            errors << "Unsupported audio format. Use OGG, OPUS, M4A, MP3, WAV or WEBM."
          end
          errors
        end

        private

        def decoded_audio_size(input)
          Base64.decode64(base64(input.audio_data)).bytesize
        rescue ArgumentError
          AUDIO_MAX_BYTES + 1
        end
      end
    end
  end
end

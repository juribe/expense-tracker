# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Audio channel. The transcript travels in `text` after speech-to-text;
    # the original filename is kept in metadata for diagnostics. Format/size
    # rules come from Rules::Audio.
    class Audio < Base
      extend Rules::Audio

      TYPE = "audio"
      PAYLOAD_KEYS = %i[text audio_data].freeze
      META_KEYS = %i[filename].freeze
      REQUIRED_FIELDS = { audio_data: "audio" }.freeze

      def self.channel_errors(input)
        audio_errors(input)
      end
    end
  end
end

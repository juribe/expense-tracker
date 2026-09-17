# frozen_string_literal: true

module Expenses
  module Inputs
    # Text + image channel (a note together with a receipt/photo). The type
    # un-structures its payload into both readers (text and image_data); the
    # image rules come from Rules::Image exactly like the image-only channel.
    class TextImage < Base
      extend Rules::Image

      TYPE = "text_image"
      PAYLOAD_KEYS = %i[text image_data].freeze
      REQUIRED_FIELDS = { text: "text", image_data: "image" }.freeze

      def text
        payload[:text]
      end

      def image_data
        payload[:image_data]
      end

      def self.channel_errors(input)
        image_errors(input)
      end
    end
  end
end

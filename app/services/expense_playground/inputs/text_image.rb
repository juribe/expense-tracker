# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Text + image channel (a note together with a receipt/photo).
    class TextImage < Base
      extend Rules::Image

      TYPE = "text_image"
      PAYLOAD_KEYS = %i[text image_data].freeze
      REQUIRED_FIELDS = { text: "text", image_data: "image" }.freeze

      def self.channel_errors(input)
        image_errors(input)
      end
    end
  end
end

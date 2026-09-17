# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Image-only channel (photo of a receipt, screenshots, chat attachments).
    # Reusable across transports: the same class converts a WhatsApp photo or
    # an upload field into the canonical Input. The class owns the image
    # reader (the way the payload is un-structured for this type), the image
    # information methods (mime_type/base64) through Rules::Image and its
    # validation rules.
    class Image < Base
      extend Rules::Image

      TYPE = "image"
      PAYLOAD_KEYS = %i[image_data].freeze
      REQUIRED_FIELDS = { image_data: "image" }.freeze

      def image_data
        payload[:image_data]
      end

      def self.channel_errors(input)
        image_errors(input)
      end
    end
  end
end

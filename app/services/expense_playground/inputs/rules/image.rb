# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    module Rules
      # Image payload rules. Extended by every typed input that accepts image
      # data (image, text_image, and channel subclasses reusing them).
      module Image
        IMAGE_MAX_BYTES = 6.megabytes

        def image_errors(input)
          return [ "Unsupported image format. Use JPEG, PNG, WebP or GIF." ] if input.image_mime_type.nil?

          errors = []
          if decoded_image_size(input) > IMAGE_MAX_BYTES
            errors << "Image is too large (max #{IMAGE_MAX_BYTES / 1.megabyte} MB)."
          end
          errors
        end

        private

        def decoded_image_size(input)
          Base64.decode64(input.image_base64).bytesize
        rescue ArgumentError
          IMAGE_MAX_BYTES + 1
        end
      end
    end
  end
end

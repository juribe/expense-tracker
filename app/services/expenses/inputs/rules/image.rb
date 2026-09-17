# frozen_string_literal: true

module Expenses
  module Inputs
    module Rules
      # Image payload rules. Extended by input classes that carry image data
      # (image, text_image, and channel subclasses reusing them). Information
      # methods (mime_type/base64) live on the typed input class and are
      # reached through the extended singleton, so validation and consumers
      # read the data through the same class.
      module Image
        IMAGE_MIME_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
        IMAGE_MAX_BYTES = 6.megabytes

        # Information methods shared by every image-bearing typed input
        # (image, text_image, and channel subclasses reusing them). They are
        # reached through the extended singleton, which is the same receiver
        # validation uses (image_errors), so the whitelist lives here too.
        def mime_type(image_data)
          DataUri.mime_type(image_data, IMAGE_MIME_TYPES)
        end

        def base64(image_data)
          DataUri.base64(image_data)
        end

        def image_errors(input)
          return [ "Unsupported image format. Use JPEG, PNG, WebP or GIF." ] if mime_type(input.image_data).nil?

          errors = []
          if decoded_image_size(input) > IMAGE_MAX_BYTES
            errors << "Image is too large (max #{IMAGE_MAX_BYTES / 1.megabyte} MB)."
          end
          errors
        end

        private

        def decoded_image_size(input)
          Base64.decode64(base64(input.image_data)).bytesize
        rescue ArgumentError
          IMAGE_MAX_BYTES + 1
        end
      end
    end
  end
end

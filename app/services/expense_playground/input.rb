# frozen_string_literal: true

module ExpensePlayground
  # Normalized ingestion input. Every source (text, image, and future
  # WhatsApp/voice/email/PDF adapters) is converted into this structure before
  # reaching the processing pipeline, so extraction never depends on the
  # transport layer or the UI.
  #
  #   ExpensePlayground::Input.new(type: :text, text: "Me gasté 50mil")
  #   ExpensePlayground::Input.new(type: :image, image_data: "data:image/jpeg;base64,...")
  class Input
    TYPES = %w[text image text_image].freeze
    IMAGE_MIME_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    MAX_IMAGE_BYTES = 6.megabytes

    attr_reader :type, :text, :image_data, :metadata

    def initialize(type:, text: nil, image_data: nil, metadata: {})
      @type = type.to_s.presence_in(TYPES)
      @text = text.to_s.strip.presence
      @image_data = image_data.to_s.presence
      @metadata = metadata || {}
    end

    def valid?
      errors.empty?
    end

    def errors
      errors = []
      errors << "Unknown input type." if type.nil?
      errors << "No text was provided." if text.blank? && needs_text?
      errors << "No image was provided." if image_data.blank? && needs_image?
      errors.concat(image_errors) if image_data.present?
      errors
    end

    def image?
      image_data.present?
    end

    def image_mime_type
      match = image_data.to_s.match(/\Adata:(image\/[a-z+]+);base64,/)
      return nil unless match

      match[1].presence_in(IMAGE_MIME_TYPES)
    end

    def image_base64
      image_data.to_s.sub(/\Adata:image\/[a-z+]+;base64,/, "")
    end

    private

    def needs_text?
      type.nil? || %w[text text_image].include?(type)
    end

    def needs_image?
      type.nil? || %w[image text_image].include?(type)
    end

    def image_errors
      errors = []
      if image_mime_type.nil?
        errors << "Unsupported image format. Use JPEG, PNG, WebP or GIF."
      elsif decoded_size > MAX_IMAGE_BYTES
        errors << "Image is too large (max #{MAX_IMAGE_BYTES / 1.megabyte} MB)."
      end
      errors
    end

    def decoded_size
      Base64.decode64(image_base64).bytesize
    rescue ArgumentError
      MAX_IMAGE_BYTES + 1
    end
  end
end

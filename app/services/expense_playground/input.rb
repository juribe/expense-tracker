# frozen_string_literal: true

module ExpensePlayground
  # Normalized ingestion input. Every source (text, image, audio, and future
  # WhatsApp/email/PDF adapters) is converted into this structure before
  # reaching the processing pipeline, so extraction never depends on the
  # transport layer or the UI.
  #
  #   ExpensePlayground::Input.new(type: :text, text: "Me gasté 50mil")
  #   ExpensePlayground::Input.new(type: :image, image_data: "data:image/jpeg;base64,...")
  #   ExpensePlayground::Input.new(type: :audio, audio_data: "data:audio/ogg;base64,...")
  class Input
    TYPES = %w[text image text_image audio].freeze
    IMAGE_MIME_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    MAX_IMAGE_BYTES = 6.megabytes

    AUDIO_MIME_EXTENSIONS = {
      "audio/ogg" => "ogg", "application/ogg" => "ogg", "audio/opus" => "opus",
      "audio/mp4" => "m4a", "audio/x-m4a" => "m4a", "audio/mpeg" => "mp3",
      "audio/mp3" => "mp3", "audio/wav" => "wav", "audio/x-wav" => "wav",
      "audio/wave" => "wav", "audio/webm" => "webm"
    }.freeze
    SUPPORTED_AUDIO_EXTENSIONS = %w[ogg opus m4a mp3 wav webm].freeze
    MAX_AUDIO_BYTES = 15.megabytes

    attr_reader :type, :text, :image_data, :audio_data, :metadata

    def initialize(type:, text: nil, image_data: nil, audio_data: nil, metadata: {})
      @type = type.to_s.presence_in(TYPES)
      @text = text.to_s.strip.presence
      @image_data = image_data.to_s.presence
      @audio_data = audio_data.to_s.presence
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
      errors << "No audio was provided." if audio_data.blank? && needs_audio?
      errors.concat(image_errors) if image_data.present?
      errors.concat(audio_errors) if audio_data.present?
      errors
    end

    def image?
      image_data.present?
    end

    def audio?
      audio_data.present?
    end

    def image_mime_type
      match = image_data.to_s.match(/\Adata:(image\/[a-z+]+);base64,/)
      return nil unless match

      match[1].presence_in(IMAGE_MIME_TYPES)
    end

    def image_base64
      image_data.to_s.sub(/\Adata:image\/[a-z+]+;base64,/, "")
    end

    # Audio mime from the data URI; falls back to the uploaded filename's
    # extension because browsers often leave the audio mime type empty.
    def audio_extension
      mime = audio_data.to_s.match(/\Adata:(audio\/[a-z0-9.+-]+)/)&.[](1)
      AUDIO_MIME_EXTENSIONS[mime.to_s] || File.extname(filename).delete(".").downcase.presence
    end

    def audio_mime_type
      audio_data.to_s.match(/\Adata:(audio\/[a-z0-9.+-]+)/)&.[](1)
    end

    def audio_base64
      audio_data.to_s.sub(/\Adata:[^;]+;base64,/, "")
    end

    def filename
      metadata[:filename].to_s
    end

    private

    def needs_text?
      type.nil? || %w[text text_image].include?(type)
    end

    def needs_image?
      type.nil? || %w[image text_image].include?(type)
    end

    def needs_audio?
      type == "audio"
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

    def audio_errors
      errors = []
      if audio_extension.in?(SUPPORTED_AUDIO_EXTENSIONS)
        errors << "Audio is too large (max #{MAX_AUDIO_BYTES / 1.megabyte} MB)." if decoded_audio_size > MAX_AUDIO_BYTES
      else
        errors << "Unsupported audio format. Use OGG, OPUS, M4A, MP3, WAV or WEBM."
      end
      errors
    end

    def decoded_audio_size
      Base64.decode64(audio_base64).bytesize
    rescue ArgumentError
      MAX_AUDIO_BYTES + 1
    end

    def decoded_size
      Base64.decode64(image_base64).bytesize
    rescue ArgumentError
      MAX_IMAGE_BYTES + 1
    end
  end
end

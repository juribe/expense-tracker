# frozen_string_literal: true

module ExpensePlayground
  # Canonical ingestion input consumed by the processing pipeline. It is
  # produced by +from_params+, which dispatches to the matching typed input
  # (ExpensePlayground::Inputs::*) and converts it through +to_input+, so
  # every channel (text, image, audio, file, future WhatsApp/email) normalizes
  # into this same structure.
  #
  # Input holds NO per-type validation: each Inputs::* class owns its own
  # validity rules (see Inputs::Base), and valid?/errors simply delegate to the
  # typed input that matches this type. Unknown types fail with "Unknown input
  # type.".
  #
  #   ExpensePlayground::Input.from_params("text", { text: "Me gasté 50mil" })
  #   ExpensePlayground::Input.new(type: :image, image_data: "data:image/jpeg;base64,...")
  class Input
    TYPES = %w[text image text_image audio file].freeze

    # Decoding whitelists used to normalize payload data URIs. Whether a value
    # is actually *valid* for the channel is decided by the typed inputs' rules.
    IMAGE_MIME_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

    AUDIO_MIME_EXTENSIONS = {
      "audio/ogg" => "ogg", "application/ogg" => "ogg", "audio/opus" => "opus",
      "audio/mp4" => "m4a", "audio/x-m4a" => "m4a", "audio/mpeg" => "mp3",
      "audio/mp3" => "mp3", "audio/wav" => "wav", "audio/x-wav" => "wav",
      "audio/wave" => "wav", "audio/webm" => "webm"
    }.freeze

    FILE_MIME_TYPES = %w[
      application/pdf text/csv
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.ms-excel
    ].freeze

    # Factory: dispatches channel params to the typed input declared for the
    # type. Unknown types produce an Input with a nil type, which fails
    # validation with "Unknown input type.".
    def self.from_params(type, params)
      typed = Inputs.for_type(type)
      return new(type: type.to_s, metadata: {}) unless typed

      typed.to_input(params)
    end

    attr_reader :type, :text, :image_data, :audio_data, :file_data, :metadata

    def initialize(type:, text: nil, image_data: nil, audio_data: nil, file_data: nil, metadata: {})
      @type = type.to_s.presence_in(TYPES)
      @text = text.to_s.strip.presence
      @image_data = image_data.to_s.presence
      @audio_data = audio_data.to_s.presence
      @file_data = file_data.to_s.presence
      @metadata = metadata || {}
    end

    def valid?
      errors.empty?
    end

    # Validation rules live in the typed inputs (Inputs::Base#validate); this
    # only looks the type up and returns the unknown-type error when there is
    # no typed input for it.
    def errors
      typed = Inputs.for_type(type)
      return [ "Unknown input type." ] unless typed

      typed.validate(self)
    end

    def image?
      image_data.present?
    end

    def audio?
      audio_data.present?
    end

    def file?
      file_data.present?
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

    def file_mime_type
      match = file_data.to_s.match(/\Adata:([^;]+);base64,/)
      return nil unless match

      match[1].presence_in(FILE_MIME_TYPES)
    end

    def file_extension
      mime = file_data.to_s.match(/\Adata:([^;]+);base64,/)&.[](1)
      case mime
      when "application/pdf" then "pdf"
      when "text/csv" then "csv"
      when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then "xlsx"
      when "application/vnd.ms-excel" then "xls"
      else
        File.extname(filename).delete(".").downcase.presence
      end
    end

    def file_base64
      file_data.to_s.sub(/\Adata:[^;]+;base64,/, "")
    end

    def file_binary
      Base64.decode64(file_base64)
    rescue ArgumentError
      nil
    end
  end
end

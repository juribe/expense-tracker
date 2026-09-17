# frozen_string_literal: true

module ExpensePlayground
  # Canonical ingestion input consumed by the processing pipeline. It is
  # produced by +from_params+, which dispatches to the matching typed input
  # (ExpensePlayground::Inputs::*) and converts it through +to_input+, so
  # every channel (text, image, audio, file, future WhatsApp/email) normalizes
  # into this same structure.
  #
  # Input is a plain data container + factory: it holds the normalized payload
  # and metadata and delegates every type-specific concern to the matching
  # typed class. Validity rules live in the typed inputs (Inputs::Base#validate)
  # and information methods (image mime type, audio extension, file data, ...)
  # live in the typed classes themselves; Input only adds one predicate per
  # registered TYPE (audio?, image?, text_image?, ...).
  #
  #   ExpensePlayground::Input.from_params("text", { text: "Me gasté 50mil" })
  #   ExpensePlayground::Input.new(type: :image, image_data: "data:image/jpeg;base64,...")
  class Input
    TYPES = %w[text image text_image audio file].freeze

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

    # One predicate per registered type: text?, image?, text_image?, audio?,
    # file? — a convenience over comparing type directly.
    TYPES.each do |type|
      define_method("#{type}?") { @type == type }
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

    def filename
      metadata[:filename].to_s
    end
  end
end

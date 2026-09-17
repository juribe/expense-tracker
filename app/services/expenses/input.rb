# frozen_string_literal: true

module Expenses
  # Canonical ingestion input consumed by the processing pipeline. It is
  # produced by +from_params+, which dispatches to the matching typed input
  # (Expenses::Inputs::*), so every channel (text, image, audio,
  # file, future WhatsApp/email) normalizes into this same structure.
  #
  # Input is a plain data envelope: it holds ONE payload (the hash of
  # type-specific fields, un-structured by the typed input that produced it)
  # plus metadata, and delegates every type-specific concern to that typed
  # class. Validity rules live in the typed inputs (Inputs::Base#validate)
  # and information methods (image mime type, audio extension, file data, ...)
  # live in the typed classes themselves; Input only adds one predicate per
  # registered TYPE (audio?, image?, text_image?, ...).
  #
  # The typed input that produces an instance destructures the payload into
  # its own readers (Expenses::Inputs::TextImage#text, ...); the
  # pipeline only has to read the single +payload+ where the field is not
  # guaranteed by the type.
  #
  #   Expenses::Input.from_params("text", { text: "Me gasté 50mil" })
  #   Expenses::Input.new(type: "text", payload: { text: "Me gasté 50mil" })
  class Input
    TYPES = %w[text image text_image audio file].freeze

    # Factory: dispatches channel params to the typed input declared for the
    # type. Unknown types produce an Input with a nil type, which fails
    # validation with "Unknown input type.".
    def self.from_params(type, params)
      typed = Inputs.for_type(type)
      return new(type: type.to_s) unless typed

      typed.to_input(params)
    end

    attr_reader :type, :payload, :metadata

    def initialize(type:, payload: {}, metadata: {})
      @type = type.to_s.presence_in(TYPES)
      @payload = payload || {}
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

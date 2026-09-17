# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Shared contract for every typed input. A subclass declares:
    #
    #   TYPE           - type string stored on the input
    #   PAYLOAD_KEYS   - which channel params become the payload (text/image/audio/file)
    #   META_KEYS      - which channel params flow into metadata (filename, password)
    #   REQUIRED_FIELDS- fields that must be present for the input to be valid
    #
    # Every typed input is itself an ExpensePlayground::Input produced by
    # +to_input+, so the pipeline consumes typed instances through the same
    # interface. Each typed class destructures its payload - a single hash -
    # into its own readers, e.g. TextImage#text and TextImage#image_data.
    #
    # Each typed input owns its own validity rules: presence comes from
    # REQUIRED_FIELDS and payload format/size rules come from the +channel_errors+
    # hook (extended through Rules::* by types that carry image/audio/file
    # payloads). The canonical ExpensePlayground::Input holds no per-type
    # validation; it delegates to the typed input that produced it.
    #
    #   class WhatsAppImage < Inputs::Image
    #     META_KEYS = %i[chat_id sender].freeze
    #   end
    #
    #   Inputs::WhatsAppImage.to_input(whatsapp_params) # => Inputs::Image
    #   Inputs::WhatsAppImage.valid?(whatsapp_params)   # => true/false
    class Base < Input
      TYPE = nil
      PAYLOAD_KEYS = %i[text image_data audio_data file_data].freeze
      META_KEYS = %i[].freeze
      REQUIRED_FIELDS = {}.freeze

      class << self
        # Channel params -> typed ExpensePlayground::Input for the pipeline.
        # All channel fields land in the single payload hash, and each typed
        # input reads back its own keys.
        def to_input(params)
          hash = symbolize(params)
          new(
            type: self::TYPE,
            payload: hash.slice(*self::PAYLOAD_KEYS).compact_blank,
            metadata: metadata(hash)
          )
        end

        # Rules this input must satisfy to be valid: required fields declared
        # by REQUIRED_FIELDS plus the payload format/size rules from
        # channel_errors. Fields are read from the input through its readers.
        def errors(params)
          validate(to_input(params))
        end

        def valid?(params)
          errors(params).empty?
        end

        # Validates an input produced by +to_input+. This is the entry point
        # ExpensePlayground::Input delegates to, so the pipeline and the typed
        # inputs share the same rules.
        def validate(input)
          presence_errors(input) + channel_errors(input)
        end

        def required_fields
          self::REQUIRED_FIELDS
        end

        private

        def channel_errors(_input)
          []
        end

        def presence_errors(input)
          self::REQUIRED_FIELDS.filter_map do |field, label|
            "No #{label} was provided." if input.public_send(field).blank?
          end
        end

        def metadata(hash)
          (hash[:metadata] || {}).merge(hash.slice(*self::META_KEYS).compact)
        end

        def symbolize(params)
          hash = params.is_a?(Hash) ? params : (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h)
          hash.deep_symbolize_keys
        end
      end
    end
  end
end

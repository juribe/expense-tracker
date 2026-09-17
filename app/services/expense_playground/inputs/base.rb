# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Shared contract for every typed input. A subclass declares:
    #
    #   TYPE           - type string stored on the canonical Input
    #   PAYLOAD_KEYS   - which channel params become payload (text/image/audio/file)
    #   META_KEYS      - which channel params flow into metadata (filename, password)
    #   REQUIRED_FIELDS- fields that must be present for the input to be valid
    #
    # Each typed input owns its own validity rules: presence comes from
    # REQUIRED_FIELDS and payload format/size rules come from the +channel_errors+
    # hook (extended through Rules::* by types that carry image/audio/file
    # payloads). The canonical ExpensePlayground::Input holds no per-type
    # validation; it delegates to the typed input that produced it.
    #
    #   class WhatsAppImage < Inputs::Image
    #     TYPE = "image"
    #     META_KEYS = %i[chat_id sender].freeze
    #   end
    #
    #   Inputs::WhatsAppImage.to_input(whatsapp_params) # => ExpensePlayground::Input
    #   Inputs::WhatsAppImage.valid?(whatsapp_params)   # => true/false
    class Base
      TYPE = nil
      PAYLOAD_KEYS = %i[text image_data audio_data file_data].freeze
      META_KEYS = %i[].freeze
      REQUIRED_FIELDS = {}.freeze

      class << self
        # Channel params -> canonical ExpensePlayground::Input for the pipeline.
        def to_input(params)
          hash = symbolize(params)
          Input.new(
            type: self::TYPE,
            **hash.slice(*self::PAYLOAD_KEYS),
            metadata: metadata(hash)
          )
        end

        # Rules this input must satisfy to be valid: required fields declared by
        # REQUIRED_FIELDS plus the payload format/size rules from channel_errors.
        def errors(params)
          validate(to_input(params))
        end

        def valid?(params)
          errors(params).empty?
        end

        # Validates a canonical Input produced by +to_input+. This is the entry
        # point ExpensePlayground::Input delegates to, so the pipeline and the
        # typed inputs share the same rules.
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

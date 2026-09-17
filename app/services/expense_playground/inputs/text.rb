# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Text-only channel (a note typed in the playground, a chat message).
    # Reusable across transports: the same class converts a WhatsApp caption
    # or an SMS into the canonical Input. The class owns the text reader (the
    # way the payload is un-structured for this type) and its validation.
    class Text < Base
      TYPE = "text"
      PAYLOAD_KEYS = %i[text].freeze
      REQUIRED_FIELDS = { text: "text" }.freeze

      def text
        payload[:text]
      end
    end
  end
end

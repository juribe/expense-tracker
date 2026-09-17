# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # Plain-text channel (typed note, voice-note note, chat message).
    class Text < Base
      TYPE = "text"
      PAYLOAD_KEYS = %i[text].freeze
      REQUIRED_FIELDS = { text: "text" }.freeze
    end
  end
end

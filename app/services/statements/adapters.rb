# frozen_string_literal: true

module Statements
  # Adapters
  # Registry of bank-specific deterministic statement parsers. Each adapter
  # recognises one statement layout and builds a Statements::Document without
  # spending an AI request; the registry is the placeholder every future
  # layout parser is slotted into, so the next file of the same bank goes
  # through it instead of the AI fallback.
  #
  # An adapter implements:
  #   .matches?(text) -> boolean (layout fingerprint)
  #   .call(extraction) -> Statements::Document (engine: :adapter)
  #
  # Example: Statements::Adapters.for(extraction.text) # => adapter or nil
  module Adapters
    # Layout parsers are registered here as they are written, e.g.
    # REGISTRY = [Adapters::BancolombiaCreditCard, Adapters::DaviviendaLoan].freeze
    REGISTRY = [].freeze

    def self.for(text)
      REGISTRY.find { |adapter| adapter.matches?(text) }
    end
  end
end

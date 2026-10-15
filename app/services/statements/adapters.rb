# frozen_string_literal: true

module Statements
  # Adapters
  # Resolves the parser for an uploaded statement. Registered bank-specific
  # parsers win first; otherwise the learned StatementFormatMapping of the
  # uploading user for that money source is consulted (its anchor lines
  # identify the layout) and a DynamicAdapter is built from the stored recipe.
  # Returns nil when nothing matches, so the caller falls back to AI extraction.
  #
  # A code adapter implements:
  #   .matches?(text) -> boolean (layout fingerprint)
  #   .call(extraction) -> Statements::Document (engine: :adapter)
  #
  # Example: Statements::Adapters.for(extraction.text, user: user, money_source: card)
  module Adapters
    # Layout parsers are registered here as they are written, e.g.
    # REGISTRY = [Adapters::BancolombiaCreditCard].freeze
    REGISTRY = [].freeze

    def self.for(text, user: nil, money_source: nil)
      REGISTRY.find { |adapter| adapter.matches?(text) } || learned(text, user, money_source)
    end

    def self.learned(text, user, money_source)
      return nil if user.nil? || money_source.nil?

      mapping = StatementFormatMapping.lookup(user: user, text: text, money_source: money_source)
      mapping && DynamicAdapter.new(mapping)
    rescue RowCompiler::InvalidSpec
      nil
    end
  end
end

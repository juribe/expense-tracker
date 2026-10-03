# frozen_string_literal: true

module Statements
  # Document
  # Canonical representation of a parsed credit-card / loan statement: the
  # statement-level summary, the period movements (AI-extracted or adapter
  # parsed, always normalized to the extractor's transaction shape), the
  # statement's own source, and which engine produced the document.
  # Pure data; parsing and persistence live elsewhere.
  #
  # Example: Statements::Document.new(engine: :ai, summary: summary, movements: [...])
  class Document
    attr_reader :summary, :movements, :source, :engine

    def initialize(summary: nil, movements: [], source: nil, engine:)
      @summary = summary
      @movements = Array(movements)
      @source = source
      @engine = engine
    end

    def expense_movements
      movements.reject { |movement| movement[:type] == "income" }
    end

    def income_movements
      movements.select { |movement| movement[:type] == "income" }
    end
  end
end

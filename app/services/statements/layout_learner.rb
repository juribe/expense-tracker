# frozen_string_literal: true

module Statements
  # LayoutLearner
  # Turns the layout recipe the AI describes during the first parse of a
  # statement format into a persisted StatementFormatMapping. The recipe is
  # validated against the very text it came from before anything is stored, so
  # a bad or low-confidence recipe is simply not learned and the next upload
  # falls back to AI again. Never raises on a bad recipe.
  #
  #   LayoutLearner.call(user: user, text: text, layout: data[:layout])
  #   # => StatementFormatMapping or nil
  class LayoutLearner
    MIN_ROWS = 3
    MIN_CONFIDENCE = 0.9

    def self.call(user:, text:, layout:, source: "ai")
      new(user: user, text: text.to_s, layout: layout, source: source).call
    end

    def initialize(user:, text:, layout:, source:)
      @user = user
      @text = text
      @layout = (layout || {}).to_h
      @source = source
    end

    def call
      return nil unless valid?

      StatementFormatMapping.record!(
        user: @user, anchors: anchors, bank: bank, sections: sections,
        row: row_spec, summary: summary_spec, confidence: confidence, source: @source
      )
    rescue Adapters::RowCompiler::InvalidSpec
      nil
    end

    private

    def valid?
      return false if anchors.empty? || !anchors.all? { |anchor| @text.include?(anchor) }
      return false if expense_headings.empty? || !expense_headings.all? { |heading| @text.include?(heading) }
      return false unless confidence.is_a?(Numeric) && confidence >= MIN_CONFIDENCE

      parsed_row_count >= MIN_ROWS
    rescue Adapters::RowCompiler::InvalidSpec
      false
    end

    # Counts the rows the recipe actually captures, so a regex that compiles
    # but mis-parses the document is rejected before it is stored.
    def parsed_row_count
      adapter = Adapters::DynamicAdapter.new(preview_mapping)
      adapter.call(Expenses::FileImport::Readers::Extraction.new(text: @text)).expense_movements.size
    end

    def preview_mapping
      StatementFormatMapping.new(sections: sections, row_spec: row_spec)
    end

    def anchors
      @anchors ||= Array(@layout["anchors"]).map { |anchor| anchor.to_s.strip }.reject(&:blank?)
    end

    def sections
      @sections ||= (@layout["sections"] || {}).to_h
    end

    def expense_headings
      @expense_headings ||= Array(sections["expenses"]).map { |heading| heading.to_s.strip }.reject(&:blank?)
    end

    def row_spec
      @row_spec ||= (@layout["row"] || @layout["row_spec"] || {}).to_h
    end

    # Only the summary selectors that actually resolve against this document
    # are kept: a label that cannot be located is dropped so it never produces
    # a spurious nil. A missing or garbled summary never blocks row learning.
    def summary_spec
      @summary_spec ||= (@layout["summary"] || {}).to_h.select do |attribute, selector|
        summary_resolves?(attribute, selector)
      end
    end

    def summary_resolves?(attribute, selector)
      return false unless selector.is_a?(Hash)

      Adapters::SummaryCompiler.compile({ attribute => selector }, text: @text).present?
    end

    def bank
      @layout["bank"].to_s.strip.presence
    end

    def confidence
      value = @layout["confidence"]
      value.is_a?(Numeric) ? value.to_f : Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

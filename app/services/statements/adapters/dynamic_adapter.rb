# frozen_string_literal: true

module Statements
  module Adapters
    # DynamicAdapter
    # Statement adapter built at runtime from a learned StatementFormatMapping
    # (the AI describes a bank's layout once; every later statement of that
    # format is parsed here with no AI call). It reproduces the billed
    # transactions (cancelled rows are dropped and income/credit movements are
    # never emitted) plus the period summary when the learned recipe carries
    # summary selectors.
    #
    #   adapter = DynamicAdapter.new(mapping)
    #   document = adapter.call(extraction)
    class DynamicAdapter
      DATE_FORMATS = {
        "DD/MM/YYYY" => "%d/%m/%Y",
        "DD-MM-YYYY" => "%d-%m-%Y",
        "YYYY-MM-DD" => "%Y-%m-%d"
      }.freeze

      def initialize(mapping, row_compiler: RowCompiler, summary_compiler: SummaryCompiler)
        @mapping = mapping
        @row_spec = (mapping.row_spec || {}).to_h
        @summary_spec = (mapping.summary_spec || {}).to_h
        @sections = (mapping.sections || {}).to_h
        @expense_headings = Array(@sections["expenses"]).map { |heading| heading.to_s.strip }
        @headings = @sections.values.flatten.map { |heading| heading.to_s.strip }
        @regexp = row_compiler.compile(@row_spec)
        @cancelled_pattern = @row_spec["cancelled_pattern"].to_s
        @date_format = date_format
        @summary_compiler = summary_compiler
      end

      def call(extraction)
        text = extraction.text.to_s
        Statements::Document.new(engine: :adapter, movements: movements(text), summary: summary(text))
      end

      private

      # The learned summary selectors let a replayed statement still carry its
      # totals (total due, minimum payment, due date, ...). Absent a spec the
      # document stays summary-less, exactly as before.
      def summary(text)
        return nil if @summary_spec.empty?

        @summary_compiler.compile(@summary_spec, text: text)
      rescue StandardError => e
        Rails.logger.warn("[Statements::Adapters::DynamicAdapter] summary skipped: #{e.class}: #{e.message}")
        nil
      end

      def movements(text)
        in_expenses = false
        text.each_line.filter_map do |line|
          stripped = line.strip
          if @headings.include?(stripped)
            in_expenses = @expense_headings.include?(stripped)
            next
          end
          next unless in_expenses

          movement_from(stripped)
        end
      end

      def movement_from(line)
        match = @regexp.match(line)
        return nil unless match
        return nil if cancelled?(match)

        date = parse_date(match[:date])
        amount = Expenses::ValueParsing.parse_amount(match[:amount])
        return nil if date.nil? || amount.nil?

        {
          date: date,
          description: description_for(match),
          amount: amount.abs,
          type: "expense",
          category: "others",
          confidence: 1.0
        }
      end

      def cancelled?(match)
        return false if @cancelled_pattern.blank?

        match[:description].to_s.match?(/#{Regexp.escape(@cancelled_pattern)}/i)
      end

      def description_for(match)
        description = match[:description].to_s.strip
        return description if description.present?

        reference = match[:ref].to_s.strip
        reference.present? ? "Compra #{reference}" : "Compra"
      end

      def parse_date(value)
        return nil if value.blank?

        format = DATE_FORMATS[@date_format]
        date = format ? Date.strptime(value, format) : Date.parse(value)
        date
      rescue ArgumentError, Date::Error, TypeError
        nil
      end

      def date_format
        field = Array(@row_spec["fields"]).find { |f| f["token"].to_s == "date" }
        field && field["format"].to_s.presence
      end
    end
  end
end

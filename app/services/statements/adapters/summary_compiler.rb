# frozen_string_literal: true

module Statements
  module Adapters
    # SummaryCompiler
    # Turns the declarative, AI-described summary selectors of a learned
    # statement layout into a Statements::Summary. Like RowCompiler, the AI
    # never writes code: it lists the printed label of each summary total
    # (total_due, min_payment, interest_charged, due_date, statement_date) and
    # this compiler finds the label and reads the first amount/date that
    # follows it. Anything that does not resolve is simply left nil.
    #
    #   SummaryCompiler.compile(spec["summary"], text: statement_text)
    #   # => Statements::Summary or nil
    class SummaryCompiler
      KINDS = {
        "total_due" => :amount,
        "min_payment" => :amount,
        "interest_charged" => :amount,
        "due_date" => :date,
        "statement_date" => :date
      }.freeze

      AMOUNT_PATTERN = /-?\s*\$?\s*\d[\d.,]*/
      DATE_PATTERN = %r{
        \d{1,2}[/-]\d{1,2}[/-]\d{4}
        |
        \d{1,2}\s+(?:ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)\w*\.?\s+\d{4}
      }ix
      WORD_DATE = /(\d{1,2})\s+(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)\w*\.?\s+(\d{4})/i
      MONTHS = {
        "ene" => 1, "feb" => 2, "mar" => 3, "abr" => 4, "may" => 5, "jun" => 6,
        "jul" => 7, "ago" => 8, "sep" => 9, "oct" => 10, "nov" => 11, "dic" => 12
      }.freeze
      DEFAULT_WINDOW = 240

      def self.compile(spec, text:)
        new(spec, text: text).compile
      end

      def initialize(spec, text:)
        @spec = (spec || {}).to_h
        @text = text.to_s
      end

      def compile
        values = KINDS.each_with_object({}) do |(attribute, kind), hash|
          value = resolve(attribute, kind)
          hash[attribute.to_sym] = value unless value.nil?
        end
        return nil if values.empty?

        Statements::Summary.new(values)
      end

      private

      def resolve(attribute, kind)
        selector = @spec[attribute]
        return nil unless selector.is_a?(Hash)

        label = selector["label"].to_s
        return nil if label.blank?

        index = @text.index(label)
        return nil unless index

        region = @text[(index + label.length), window(selector)].to_s
        case kind
        when :amount then nth_amount(region, selector)
        when :date then nth_date(region, selector)
        end
      end

      def window(selector)
        value = selector["window"].to_i
        value.positive? ? value : DEFAULT_WINDOW
      end

      def nth_amount(region, selector)
        match = nth(region.scan(AMOUNT_PATTERN), selector)
        return nil if match.blank?

        Expenses::ValueParsing.parse_amount(match, allow_zero: true)
      end

      def nth_date(region, selector)
        match = nth(region.scan(DATE_PATTERN), selector)
        return nil if match.blank?

        parse_date(match)
      end

      def nth(matches, selector)
        position = selector["nth"].to_i
        matches[position.positive? ? position - 1 : 0]
      end

      def parse_date(value)
        text = value.to_s
        if (match = WORD_DATE.match(text))
          Date.new(match[3].to_i, MONTHS[match[2].downcase], match[1].to_i)
        else
          Date.strptime(text, text.include?("/") ? "%d/%m/%Y" : "%d-%m-%Y")
        end
      rescue ArgumentError, Date::Error, TypeError
        nil
      end
    end
  end
end

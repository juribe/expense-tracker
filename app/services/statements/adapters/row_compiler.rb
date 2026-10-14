# frozen_string_literal: true

module Statements
  module Adapters
    # RowCompiler
    # Turns the declarative, AI-described row recipe of a learned statement
    # layout into a Ruby Regexp. The AI never writes code: it lists the ordered
    # tokens of a transaction line (date, ref, description, amount, ...) and
    # this compiler renders the matching + named capture groups
    # deterministically, so the same recipe always compiles to the same regex.
    #
    #   regexp = RowCompiler.compile(spec["row"])
    #   regexp.match(line)&.[](:amount)
    class RowCompiler
      class InvalidSpec < StandardError; end

      DATE_PATTERNS = {
        "DD/MM/YYYY" => '\\d{2}/\\d{2}/\\d{4}',
        "DD-MM-YYYY" => '\\d{2}-\\d{2}-\\d{4}',
        "YYYY-MM-DD" => '\\d{4}-\\d{2}-\\d{2}'
      }.freeze
      DEFAULT_DATE_PATTERN = '\\d{2}[/-]\\d{2}[/-]\\d{4}'

      def self.compile(row_spec)
        new(row_spec).compile
      end

      def initialize(row_spec)
        @row_spec = (row_spec || {}).to_h
        @fields = Array(@row_spec["fields"])
      end

      def compile
        validate!
        Regexp.new("\\A\\s*#{fragments.join('\\s*')}\\z")
      end

      private

      def validate!
        tokens = @fields.map { |field| field["token"].to_s }
        raise InvalidSpec, "row spec has no fields" if tokens.empty?
        raise InvalidSpec, "row spec is missing a date token" unless tokens.include?("date")
        raise InvalidSpec, "row spec is missing an amount token" unless tokens.include?("amount")
      end

      def fragments
        @fields.map { |field| fragment_for(field) }
      end

      def fragment_for(field)
        case field["token"].to_s
        when "date" then "(?<date>#{date_pattern(field['format'])})"
        when "ref" then ref_fragment(field)
        when "description" then description_fragment(field)
        when "amount" then amount_fragment(field)
        when "installments" then '(?<installments>\d+/\d+)'
        else ".*"
        end
      end

      def date_pattern(format)
        DATE_PATTERNS[format.to_s] || DEFAULT_DATE_PATTERN
      end

      def ref_fragment(field)
        length = field["length"].to_i
        length.positive? ? "(?<ref>\\d{#{length}})" : "(?<ref>\\d+)"
      end

      # The description can never cross a currency amount (the "$"), which is
      # what keeps the transaction value — not a later capital/saldo column —
      # flagged as the amount.
      def description_fragment(field)
        capture = "(?<description>[^$]+?)"
        field["optional"] ? "(?:#{capture}\\s+)?" : capture
      end

      def amount_fragment(field)
        currency = field["currency"].to_s.strip
        prefix = currency.empty? ? "" : "#{Regexp.escape(currency)}\\s*"
        "#{prefix}(?<amount>-?[\\d.,]+)"
      end
    end
  end
end

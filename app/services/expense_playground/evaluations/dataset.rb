# frozen_string_literal: true

require "csv"
require "stringio"

module ExpensePlayground
  module Evaluations
    # Loads and validates an evaluation dataset. CSV is the initial format;
    # .build dispatches by file extension so XLS/XLSX loaders can be added
    # later without touching the evaluation engine.
    #
    # Required columns: message, expected_json
    #   message        the natural-language expense text sent to the pipeline
    #   expected_json  the expected FINAL result as a JSON document
    #
    # Invalid rows (blank message / malformed expected_json) are reported and
    # never handed to the execution engine.
    #
    #   dataset = Dataset.build(content: csv_text, filename: "gastos_v2.csv")
    #   dataset.valid?   # => true
    #   dataset.rows     # => [Row(number:, message:, expected_json:)]
    #   dataset.checksum # => sha256 digest used as the dataset version
    class Dataset
      REQUIRED_COLUMNS = %w[message expected_json].freeze

      class Invalid < StandardError; end

      Row = Struct.new(:number, :message, :expected_json, keyword_init: true) do
        def message?
          message.to_s.present?
        end
      end

      def self.build(content:, filename: nil)
        extension = File.extname(filename.to_s).downcase
        raise Invalid, "XLS/XLSX datasets are not supported yet. Export the dataset as CSV." if extension.in?(%w[.xls .xlsx])

        new(content: content, filename: filename)
      end

      attr_reader :filename, :checksum, :rows, :errors

      def initialize(content:, filename: nil)
        @content = content
        @filename = filename
        @source = decode(content)
        @checksum = Digest::SHA256.hexdigest(@source.to_s)
        @rows = []
        @errors = []
      end

      def name
        filename.presence || "dataset.csv"
      end

      def valid?
        @rows = []
        @errors = []
        source = @source
        if source.blank?
          @errors << "The dataset file is empty."
          return false
        end
        unless required_columns_present?(source)
          return false
        end

        begin
          CSV.new(StringIO.new(source), headers: true).each.with_index(2) do |csv_row, line|
            row = build_row(csv_row, line)
            if row
              @rows << row
            else
              @errors << "Row #{line}: message must not be empty or expected_json is not valid JSON."
            end
          end
        rescue CSV::MalformedCSVError => e
          @errors << "The dataset is not a well-formed CSV file (#{e.message})."
        end

        @errors.empty?
      end

      def each_row(&block)
        return enum_for(:each_row) unless block

        rows.each(&block)
      end

      private

      def required_columns_present?(source)
        first_line = source.to_s.lines.first
        headers = CSV.parse_line(first_line).to_a.map(&:to_s).map(&:strip)
        missing = REQUIRED_COLUMNS - headers
        return true if missing.empty?

        @errors << "Missing required column(s): #{missing.join(', ')}. Expected: #{REQUIRED_COLUMNS.join(', ')}."
        false
      end

      def build_row(csv_row, line)
        message = csv_row["message"].to_s.strip
        expected_raw = csv_row["expected_json"].to_s.strip
        return nil if message.blank?

        begin
          expected = JSON.parse(expected_raw)
        rescue JSON::ParserError
          return nil
        end

        Row.new(number: line, message: message, expected_json: expected)
      rescue CSV::MalformedCSVError
        nil
      end

      def decode(content)
        text = content.to_s.strip
        return text unless text.start_with?("data:")

        if text.match?(/;base64,/)
          _, encoded = text.split(";base64,", 2)
          Base64.decode64(encoded.to_s)
        else
          text.split(",", 2).last.to_s
        end
      end
    end
  end
end

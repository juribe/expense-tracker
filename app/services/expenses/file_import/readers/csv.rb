# frozen_string_literal: true

require "csv"

module Expenses
  module FileImport
    module Readers
      # CSV reader. A single parse feeds both pipeline consumers: the preview
      # text the AI statement extractor would receive when the deterministic
      # pass fails, and the raw rows + headers the deterministic pass walks.
      class Csv < Base
        def call
          table = parse_csv
          return Extraction.empty if table.nil? || table.empty?

          headers = table.headers.compact.map(&:to_s)
          rows = []
          lines = []
          table.each do |row|
            fields = headers.map { |header| row[header].to_s.strip }.reject(&:blank?)
            lines << fields.join(" | ")
            rows << row.fields
          end
          Extraction.new(text: lines.join("\n"), rows: rows, headers: headers)
        end

        private

        def parse_csv
          require "stringio"
          CSV.parse(StringIO.new(decode_to_utf8(binary).delete("\r")), headers: true)
        end
      end
    end
  end
end

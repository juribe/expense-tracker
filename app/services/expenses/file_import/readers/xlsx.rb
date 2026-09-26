# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      # Excel reader. Roo streams the first sheet once, producing both the
      # preview text and the tabular rows (header row = first row with at
      # least two non-empty cells, data rows after it). Without Roo, a raw
      # zip/XML scan still salvages a preview text for the AI fallback.
      class Xlsx < Base
        def call
          return raw_fallback unless defined?(Roo::Spreadsheet)

          with_tempfile("xlsx") do |tmp|
            sheet = Roo::Spreadsheet.open(tmp.path).sheet(0)
            return Extraction.empty unless sheet

            rows = []
            sheet.each_row_streaming(Array: true) { |row| rows << row.map { |cell| cell.to_s.strip } }
            build_extraction(rows)
          end
        rescue StandardError => e
          Rails.logger.warn("[FileProcessor] xlsx tabular read skipped: #{e.class}: #{e.message}")
          Extraction.empty
        end

        private

        def build_extraction(rows)
          text = rows.select { |cells| cells.any?(&:present?) }
                     .map { |cells| cells.reject(&:blank?).join(" | ") }
                     .join("\n")
          header_idx = rows.index { |row| row.count(&:present?) >= 2 }
          return Extraction.new(text: text, rows: [], headers: []) unless header_idx

          data_rows = rows[(header_idx + 1)..].reject { |row| row.all?(&:blank?) }
          Extraction.new(text: text, rows: data_rows, headers: rows[header_idx])
        end

        def raw_fallback
          require "zip"
          Zip::InputStream.open(StringIO.new(binary)) do |io|
            while (entry = io.get_next_entry)
              next unless entry.name.include?("sheet") && entry.name.end_with?(".xml")

              content = io.read
              cells = content.scan(/<v>([^<]+)<\/v>/).flatten
              if cells.any?
                text = cells.each_slice(10).map { |slice| slice.join(" | ") }.join("\n")
                return Extraction.new(text: text, rows: [], headers: [])
              end
            end
          end
          Extraction.empty
        rescue StandardError
          Extraction.empty
        end
      end
    end
  end
end

# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      # Excel reader. Roo streams the first sheet once, producing both the
      # preview text and the tabular rows (header row = first row with at
      # least two non-empty cells, data rows after it). Without Roo, a raw
      # zip/XML scan still salvages a preview text for the AI fallback.
      class Xlsx < Base
        MAX_ENTERED_BYTES = 5.megabytes
        MAX_ENTRIES = 50
        MAX_ROWS = 10_000
        CHUNK_BYTES = 64 * 1024

        def call
          return raw_fallback unless defined?(Roo::Spreadsheet)

          with_tempfile("xlsx") do |tmp|
            sheet = Roo::Spreadsheet.open(tmp.path).sheet(0)
            return Extraction.empty unless sheet

            rows = []
            sheet.each_row_streaming(Array: true) do |row|
              rows << row.map { |cell| cell.to_s.strip }
              break if rows.size >= MAX_ROWS
            end
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
            scanned = 0
            while (entry = io.get_next_entry)
              scanned += 1
              break if scanned > MAX_ENTRIES
              next unless entry.name.include?("sheet") && entry.name.end_with?(".xml")
              next if entry.size.to_i > max_entry_bytes

              content = read_bounded(io)
              return Extraction.empty if content.nil?

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

        # A small compressed entry can declare (or stream) a huge payload; read
        # in chunks and stop as soon as the decompressed bound is crossed.
        def read_bounded(io)
          buffer = +""
          while (chunk = io.read(CHUNK_BYTES))
            buffer << chunk
            return nil if buffer.bytesize > max_entry_bytes
          end
          buffer
        end

        def max_entry_bytes
          ENV.fetch("XLSX_MAX_ENTRY_BYTES", MAX_ENTERED_BYTES).to_i.clamp(1, MAX_ENTERED_BYTES)
        end
      end
    end
  end
end

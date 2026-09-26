# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      # What a format reader hands back to the pipeline: the preview text
      # (consumed by the AI statement extractor fallback) and, for tabular
      # formats, the raw data rows and header row for the deterministic pass.
      Extraction = Struct.new(:text, :rows, :headers, keyword_init: true) do
        def self.empty
          new(text: nil, rows: [], headers: [])
        end

        def tabular?
          rows.any? || headers.any?
        end
      end
    end
  end
end

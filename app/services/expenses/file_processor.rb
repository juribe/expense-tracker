# frozen_string_literal: true

module Expenses
  # Processes uploaded files (PDF, CSV, Excel) through the import pipeline.
  # Extracts text from the file, runs deterministic/AI extraction, and
  # returns structured candidates for preview and batch creation.
  #
  # The implementation lives in FileImport, organized as a strategy per file
  # format (Readers::Csv/Xlsx/Pdf), a tabular column mapper, a row→candidate
  # builder and per-import enrichers, all sharing one ImportContext cache.
  #
  #   result = FileProcessor.call(user: user, file_data: "data:...", filename: "stmt.pdf")
  #   result.ok?        # => true
  #   result.candidates # => [ExpenseCandidate, ...]
  #   result.sources    # => [ParsedStatement, ...]
  class FileProcessor
    Result = FileImport::Result

    class << self
      def call(user:, file_data:, filename: nil, password: nil)
        FileImport::Pipeline.call(user: user, file_data: file_data, filename: filename, password: password)
      end
    end
  end
end

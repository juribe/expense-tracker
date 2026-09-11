# frozen_string_literal: true

module Ai
  # Resolves the column mapping for a spreadsheet import. Known formats are
  # answered from SpreadsheetFormatMapping without any AI call; unknown
  # formats send only the headers and a few truncated sample rows to the
  # strong model once, and the mapping is persisted for future imports.
  #
  #   result = Ai::SpreadsheetMapper.call(user: user, headers: headers, sample_rows: rows.first(5))
  #   result[:ok?]     # => true
  #   result[:mapping] # => { "date_column" => "Fecha", ... }
  #   result[:source]  # => "cache" | "strong_ai"
  class SpreadsheetMapper
    SAMPLE_ROW_LIMIT = 5
    CELL_CHAR_LIMIT = 80

    def self.call(user:, headers:, sample_rows: [], bank: nil)
      new(user: user, headers: headers, sample_rows: sample_rows, bank: bank).call
    end

    def initialize(user:, headers:, sample_rows:, bank: nil)
      @user = user
      @headers = Array(headers).map(&:to_s)
      @sample_rows = sanitize_rows(sample_rows)
      @bank = bank
    end

    def call
      known = SpreadsheetFormatMapping.lookup(user: @user, headers: @headers)
      return success(known.mapping, "cache", known.confidence) if known

      result = Router.call(task: :spreadsheet_mapping,
                           input: { headers: @headers, sample_rows: @sample_rows },
                           context: { user: @user })
      return failure(result.error || "AI mapping failed") unless result.ok?

      SpreadsheetFormatMapping.record!(user: @user, headers: @headers, bank: @bank,
                                       mapping: result.data, source: result.strategy,
                                       confidence: result.confidence)
      success(result.data, result.strategy, result.confidence)
    end

    private

    def success(mapping, source, confidence)
      { ok?: true, mapping: mapping, source: source, confidence: confidence, error: nil }
    end

    def failure(error)
      { ok?: false, mapping: nil, source: nil, confidence: nil, error: error }
    end

    def sanitize_rows(rows)
      Array(rows).first(SAMPLE_ROW_LIMIT).map do |row|
        Array(row).map { |cell| cell.to_s.truncate(CELL_CHAR_LIMIT) }
      end
    end
  end
end

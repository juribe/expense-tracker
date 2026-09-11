# frozen_string_literal: true

module Ai
  module Tasks
    # Column mapping for an unknown spreadsheet format. Only the structural
    # profile (headers + a few truncated sample rows) is sent to the model —
    # never the whole file — and the resulting mapping is then applied to
    # every row deterministically.
    #
    # input: { headers: ["Fecha", "Descripción", "Débito", "Crédito"],
    #          sample_rows: [ ["2026-09-01", "DIDI FOOD", "45000", ""], ... ] }
    # data:  { "date_column" => "Fecha", "description_column" => "Descripción",
    #          "debit_column" => "Débito", "credit_column" => "Crédito",
    #          "amount_column" => nil, "balance_column" => nil }
    class SpreadsheetMapping < Base
      MAPPING_KEYS = %w[date_column description_column amount_column debit_column credit_column balance_column].freeze

      # Structure mapping requires reliable reasoning; keep it on the strong
      # tier (the mapping is then cached, so this runs at most once per format).
      def tiers
        %i[strong]
      end

      def timeout
        40
      end

      def messages(input, _context)
        [
          { role: "system", content: system_prompt },
          { role: "user", content: structure_document(input) }
        ]
      end

      def parse(content, input, _context)
        payload = parse_json(content)
        mapping = payload["mapping"].is_a?(Hash) ? payload["mapping"] : payload

        headers = Array(input[:headers]).map(&:to_s)
        normalized = {}
        MAPPING_KEYS.each do |key|
          value = mapping[key].to_s.strip.presence
          normalized[key] = headers.include?(value) ? value : nil
        end
        if normalized["date_column"].nil? || normalized["description_column"].nil?
          raise InvalidResponse, "mapping is missing the date and/or description column"
        end
        if normalized["amount_column"].nil? && normalized["debit_column"].nil? && normalized["credit_column"].nil?
          raise InvalidResponse, "mapping is missing an amount, debit or credit column"
        end

        confidence = payload["confidence"]
        confidence = confidence.is_a?(Numeric) ? Float(confidence).clamp(0.0, 1.0) : 0.9
        { data: normalized, confidence: confidence }
      end

      private

      def structure_document(input)
        rows = Array(input[:sample_rows]).first(5).map do |row|
          Array(row).map { |cell| cell.to_s.truncate(80) }.join(" | ")
        end
        <<~PROMPT
          Spreadsheet headers (in order):
          #{Array(input[:headers]).each_with_index.map { |h, i| "#{i + 1}. #{h}" }.join("\n")}

          Sample rows:
          #{rows.join("\n")}
        PROMPT
      end

      def system_prompt
        <<~PROMPT
          You identify the transaction column layout of a bank statement spreadsheet
          (CSV / Excel). Only this header/sample structure is provided, not the full file.
          Rules:
          - date_column: the column with the transaction date.
          - description_column: the column with the merchant/description text.
          - amount_column: a single signed amount column when the format has one.
          - debit_column / credit_column: separate expense/income columns when the
            format splits them (use BOTH when present; leave amount_column null).
          - balance_column: a running-balance column when present.
          - Every value must be one of the provided header names, spelled exactly,
            or null when the column does not exist.
          - Include a confidence between 0 and 1.
          Respond with ONLY JSON of the shape:
          {"mapping":{"date_column":"Fecha","description_column":"Descripción",
            "amount_column":null,"debit_column":"Débito","credit_column":"Crédito",
            "balance_column":"Saldo"},"confidence":0.95}
        PROMPT
      end
    end
  end
end

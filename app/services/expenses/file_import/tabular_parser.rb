# frozen_string_literal: true

module Expenses
  module FileImport
    # Resolves which columns carry date/description/amount for tabular rows.
    # Heuristic alias matching runs first so common bank exports (spanish and
    # english) parse without any AI call; unknown layouts are resolved through
    # the known-format registry / a single structure-mapping AI call, cached
    # per header fingerprint inside Ai::SpreadsheetMapper.
    class TabularParser
      DATE_HEADERS = /\b(?:fecha|fech|date|posted|transaction date|fch|movimiento)\b/i
      DESC_HEADERS = /\b(?:descripcion|descripci[oó]n|description|detalle|concepto|concept|actividad|activity|comercio|comerciante|merchant|referencia|reference|nombre|name)\b/i
      AMOUNT_HEADERS = /\b(?:valor|monto|amount|debito|cargo|credito|cr[eé]dito|debit|credit|importe|total|valor pagado)\b/i
      EXPENSE_HEADERS = /\b(?:debito|cargo|debit|expense|valor)\b/i
      INCOME_HEADERS = /\b(?:credito|cr[eé]dito|credit|income|valor)\b/i

      # Column positions for the transaction fields. `expense_only` marks a
      # dedicated debit/cargo column: when present, its value wins over the
      # generic amount column for expense rows.
      Mapping = Struct.new(:date, :description, :amount, :expense_only, keyword_init: true)

      def self.call(user:, headers:, rows:)
        new(user: user).call(headers, rows)
      end

      def initialize(user:)
        @user = user
      end

      def call(headers, rows)
        heuristic(headers) || ai_structure(headers, rows)
      end

      private

      def heuristic(headers)
        normalized = headers.map { |h| h.to_s.downcase.gsub(/\s+/, " ").strip }

        date_idx = normalized.index { |h| h.match?(DATE_HEADERS) }
        desc_idx = normalized.index { |h| h.match?(DESC_HEADERS) }
        expense_idx = normalized.index { |h| h.match?(EXPENSE_HEADERS) && !h.match?(INCOME_HEADERS) && !h.match?(DESC_HEADERS) }
        # Prefer a dedicated debit/cargo column for the amount; otherwise fall
        # back to a generic "valor"/"amount" column.
        generic_idx = normalized.index { |h| h.match?(AMOUNT_HEADERS) }
        amount_idx = expense_idx || generic_idx
        return nil unless date_idx && desc_idx && amount_idx

        Mapping.new(date: date_idx, description: desc_idx, amount: amount_idx, expense_only: expense_idx)
      end

      def ai_structure(headers, rows)
        result = Ai::SpreadsheetMapper.call(user: @user, headers: headers, sample_rows: rows.first(5))
        return nil unless result[:ok?]

        mapping = result[:mapping] || {}
        date_idx = header_index(headers, mapping["date_column"])
        desc_idx = header_index(headers, mapping["description_column"])
        amount_idx = header_index(headers, mapping["debit_column"]) ||
                     header_index(headers, mapping["amount_column"]) ||
                     header_index(headers, mapping["credit_column"])
        return nil unless date_idx && desc_idx && amount_idx

        Mapping.new(date: date_idx, description: desc_idx, amount: amount_idx,
                    expense_only: header_index(headers, mapping["debit_column"]))
      end

      def header_index(headers, name)
        return nil if name.blank?

        headers.index { |header| header.to_s.strip.casecmp?(name.strip) }
      end
    end
  end
end

# frozen_string_literal: true

require "csv"

module Expenses
  # Renders the expenses CSV export. The scope may come paginated (the HTML
  # page's will_paginate collection); the export must always cover every
  # filtered row, so limit/offset are stripped before iterating.
  #
  #   csv_text = Expenses::CsvExporter.call(scope)  # -> String
  #   Expenses::CsvExporter.filename                 # -> "expenses-YYYY-MM-DD.csv"
  class CsvExporter
    HEADERS = %w[date description category amount source].freeze
    # Excel/LibreOffice treat these leading characters as formulas.
    FORMULA_PREFIXES = %w[= + - @ \t \r].freeze

    def self.call(scope)
      new.call(scope)
    end

    def self.filename
      "expenses-#{Date.current}.csv"
    end

    def call(scope)
      CSV.generate(headers: true) do |rows|
        rows << HEADERS
        scope.except(:offset, :limit).each do |expense|
          rows << [
            expense.date,
            safe_text(expense.description),
            safe_text(expense.category&.name),
            expense.amount.to_s,
            safe_text(expense.money_source&.name)
          ]
        end
      end
    end

    private

    # A crafted description/category/source could execute as a formula when
    # the export is opened in a spreadsheet; the leading apostrophe neutralizes it.
    def safe_text(value)
      text = value.to_s
      return text if text.empty?
      return text unless FORMULA_PREFIXES.any? { |prefix| text.start_with?(prefix) }

      "'#{text}"
    end
  end
end

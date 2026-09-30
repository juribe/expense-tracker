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

    def self.call(scope)
      new.call(scope)
    end

    def self.filename
      "expenses-#{Date.today}.csv"
    end

    def call(scope)
      CSV.generate(headers: true) do |rows|
        rows << HEADERS
        scope.except(:offset, :limit).find_each do |expense|
          rows << [
            expense.date,
            expense.description.to_s,
            expense.category&.name.to_s,
            expense.amount.to_s,
            expense.money_source&.name.to_s
          ]
        end
      end
    end
  end
end

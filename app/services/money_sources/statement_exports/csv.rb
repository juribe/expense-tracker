# frozen_string_literal: true

require "csv"

module MoneySources
  module StatementExports
    # Renders a money source statement as CSV, one row per movement.
    class Csv < Base
      def call
        CSV.generate(headers: true) do |rows|
          rows << HEADERS
          movements.each { |movement| rows << row(movement) }
        end
      end

      private

      def extension
        "csv"
      end
    end
  end
end

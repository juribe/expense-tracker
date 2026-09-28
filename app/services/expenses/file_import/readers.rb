# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      EXTENSION_READERS = { "csv" => "Csv", "xlsx" => "Xlsx", "xls" => "Xlsx", "pdf" => "Pdf" }.freeze

      def self.for(extension)
        name = EXTENSION_READERS[extension]
        name && const_get(name)
      end
    end
  end
end

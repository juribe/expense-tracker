# frozen_string_literal: true

module Expenses
  module FileImport
    module Enrichers
      # Post-extraction layers applied to every candidate batch before
      # preview: category classification, money source linking and
      # confidence scoring. Each enricher is instantiated once per import so
      # its internal caches are shared across all rows of the batch.
    end
  end
end

# frozen_string_literal: true

module Expenses
  module FileImport
    Result = Struct.new(:ok?, :candidates, :sources, :errors, :warnings, :step_results, :duplicates,
                        keyword_init: true)
  end
end

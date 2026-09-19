# frozen_string_literal: true

module Expenses
  # What every entry-point gets back, shared by every channel processor
  # (text/image/audio) and the file pipeline.
  Result = Struct.new(:candidates, :steps, :errors, :warnings, :duration_ms, :engine, keyword_init: true) do
    def ok?
      candidates.present? && candidates.all?(&:valid?) && errors.empty?
    end
  end
end

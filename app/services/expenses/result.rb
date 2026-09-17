# frozen_string_literal: true

module Expenses
  # What every entry-point gets back, shared by every channel processor
  # (text/image/audio) and the file pipeline.
  Result = Struct.new(:candidate, :steps, :errors, :warnings, :duration_ms, :engine, keyword_init: true) do
    def ok?
      candidate.present? && candidate.valid? && errors.empty?
    end
  end
end

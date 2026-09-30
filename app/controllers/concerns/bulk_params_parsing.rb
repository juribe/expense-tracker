# frozen_string_literal: true

# Shared parsing of bulk-selection id lists across controllers. Ids arrive as
# arrays, comma-joined strings ("3,7"), or single values; zero and blank
# fragments are rejected.
module BulkParamsParsing
  def parse_ids(raw)
    Array(raw).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
  end
end

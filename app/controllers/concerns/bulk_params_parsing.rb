# frozen_string_literal: true

# Shared parsing of bulk-selection id lists across controllers. Ids arrive as
# arrays, comma-joined strings ("id1,id2"), or single values; invalid and blank
# fragments are rejected. Keep in sync with app/lib/uuid_params.rb.
module BulkParamsParsing
  def parse_ids(raw)
    UuidParams.parse_ids(raw)
  end
end

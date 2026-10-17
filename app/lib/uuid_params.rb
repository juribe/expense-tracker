# frozen_string_literal: true

# Shared helpers for parsing user-supplied values that reference UUID primary
# keys (bulk selections like "id1,id2" and single record references). Invalid
# or empty fragments are rejected instead of blowing up on the uuid cast.
module UuidParams
  UUID_EXPRESSION = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  module_function

  def parse_ids(raw)
    Array(raw)
      .flat_map { |value| value.to_s.split(",") }
      .map(&:strip)
      .select { |value| value.match?(UUID_EXPRESSION) }
      .uniq
  end

  def normalize(raw)
    value = Array(raw).first.to_s.strip
    value.match?(UUID_EXPRESSION) ? value : nil
  end
end

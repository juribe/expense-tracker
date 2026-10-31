# frozen_string_literal: true

module Mcp
  # Idempotency
  # Wraps a write so a retried idempotency key returns the original result
  # instead of creating a second financial record. The placeholder row is
  # inserted inside the same transaction as the operation, so concurrent
  # retries block on the unique index instead of both writing.
  #
  # Example: Mcp::Idempotency.run(user: user, key: key, tool: "create_expense",
  #   arguments: { amount: "1000" }) { ... }
  module Idempotency
    module_function

    def run(user:, key:, tool:, arguments:)
      normalized = UuidParams.normalize(key)
      return yield if normalized.nil? && key.blank?
      raise Mcp::Error.new("INVALID_ARGUMENT", "idempotency_key must be a UUID.") if normalized.nil?

      digest = digest_for(tool: tool, arguments: arguments)
      existing = find_record(user, normalized)
      return replay(existing, digest) if existing

      ActiveRecord::Base.transaction do
        record = McpIdempotencyRecord.create!(
          user: user,
          idempotency_key: normalized,
          tool_name: tool,
          request_digest: digest,
          response: {}
        )
        data = yield
        record.update!(response: data, resource_id: data[:id] || data["id"])
        data
      end
    rescue ActiveRecord::RecordNotUnique
      existing = find_record(user, normalized)
      raise unless existing

      replay(existing, digest)
    end

    def digest_for(tool:, arguments:)
      Digest::SHA256.hexdigest(JSON.generate(tool: tool, arguments: arguments))
    end

    def find_record(user, key)
      McpIdempotencyRecord.find_by(user_id: user.id, idempotency_key: key)
    end

    def replay(record, digest)
      unless record.request_digest == digest
        raise Mcp::Error.new("CONFLICT_DUPLICATE",
                             "idempotency_key was already used with different arguments.")
      end

      record.response
    end
  end
end

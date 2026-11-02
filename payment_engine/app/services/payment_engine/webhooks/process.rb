# frozen_string_literal: true

module PaymentEngine
  module Webhooks
    class Process
      def self.call(webhook_event:, actor: nil)
        # Idempotency: if already processed, skip
        if webhook_event.processed?
          return PaymentEngine::Result.new(success: true, record: webhook_event, metadata: { skipped: true })
        end
        ActiveRecord::Base.transaction do
          webhook_event.update!(status: "processed", processed_at: Time.current, attempts: webhook_event.attempts.to_i + 1)
          AuditLog.create!(
            actor_type: actor&.class&.name || "System",
            actor_id: actor&.id,
            action: "webhook.processed",
            auditable_type: webhook_event.class.name,
            auditable_id: webhook_event.id,
            reason: nil,
            changes: { status: "processed" },
            metadata: {}
          )
        end
        PaymentEngine::Result.new(success: true, record: webhook_event)
      rescue StandardError => e
        webhook_event.update!(status: "failed", processing_result: e.message, attempts: webhook_event.attempts.to_i + 1) rescue nil
        PaymentEngine::Result.new(success: false, errors: [e.message])
      end
    end
  end
end

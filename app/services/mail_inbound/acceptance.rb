# frozen_string_literal: true

module MailInbound
  # Acceptance
  # Persists a normalized provider message as a ProcessedEmail and enqueues
  # the existing expense pipeline job. Idempotence is per user: two users may
  # hold rows for the same provider message id.
  class Acceptance
    TERMINAL_STATUSES = %w[queued processing processed ignored needs_review].freeze

    def initialize(delivery:, message:)
      @delivery = delivery
      @message = message
    end

    def call
      record = ProcessedEmail.find_or_initialize_by(
        user: @message.user,
        provider: @message.provider,
        message_id: @message.external_id
      )
      return [ record, false ] if record.persisted? && terminal?(record.status)

      save_queued(record)
      enqueue(record)
      [ record, true ]
    rescue ActiveRecord::RecordNotUnique
      record = ProcessedEmail.find_by!(
        user: @message.user,
        provider: @message.provider,
        message_id: @message.external_id
      )
      [ record, false ]
    end

    private

    def terminal?(status)
      TERMINAL_STATUSES.include?(status.to_s)
    end

    def save_queued(record)
      record.user = @message.user
      record.status = "queued"
      record.failure_reason = nil
      record.processed_at = nil
      record.payload = JSON.generate("email" => @message.to_payload)
      record.save!
    end

    def enqueue(record)
      MailInboundProcessJob.perform_later(record.id)
    rescue StandardError
      record.update_columns(
        status: "failed",
        failure_reason: "enqueue failed",
        updated_at: Time.current
      )
      raise QueueError, "could not enqueue inbound processing job"
    end
  end
end

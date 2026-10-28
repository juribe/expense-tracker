# frozen_string_literal: true

# Runs the expense import pipeline for one normalized inbound email.
class MailInboundProcessJob < ApplicationJob
  queue_as :default

  TERMINAL_STATUSES = %w[processed ignored needs_review].freeze

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, _error|
    # Retries are exhausted: this row will not be processed again, so its
    # stored email is no longer needed.
    ProcessedEmail.find_by(id: job.arguments.first)&.purge_email_content!
  end

  def perform(processed_email_id)
    email = ProcessedEmail.find(processed_email_id)
    return unless MailInbound::PROVIDERS.key?(email.provider)

    if terminal?(email)
      email.purge_email_content!
      return
    end

    process_email(email)
    email.purge_email_content!
  rescue StandardError => e
    Rails.logger.error("[MailInboundProcessJob] id=#{processed_email_id} failed: #{e.class}")
    raise
  end

  private

  # A terminal row is never reprocessed: its content may already be purged, and
  # a duplicate job must not turn a successful import into a failure. Failed
  # rows stay retryable while their stored email is still present.
  def terminal?(email)
    email.status.in?(TERMINAL_STATUSES) ||
      (email.failed? && email.payload_data["email"].blank?)
  end

  def process_email(email)
    message = email.payload_data["email"]
    if message.blank?
      email.update!(
        status: "failed",
        failure_reason: "stored email payload missing",
        processed_at: Time.current
      )
      return
    end

    if MailInbound::ForwardingVerificationDetector.verification_message?(message)
      MailInbound::ForwardingVerificationDetector.store!(
        user: email.user,
        message: message,
        processed_email: email
      )
      email.update!(
        status: "ignored",
        failure_reason: "gmail forwarding verification",
        processed_at: Time.current
      )
      Rails.logger.info("[MailInboundProcessJob] id=#{email.id} status=ignored reason=forwarding_verification")
      return
    end

    origin = MailInbound::SourceRegistrar.origin_email(message)
    source = MailInbound::SourceRegistrar.find_or_register(email.user, origin)

    unless source&.active?
      email.update!(
        status: "ignored",
        failure_reason: "email source not accepted",
        processed_at: Time.current
      )
      Rails.logger.info("[MailInboundProcessJob] id=#{email.id} status=ignored reason=source_not_accepted")
      return
    end

    result = MailInbound::Processor.new(
      user: email.user,
      provider: email.provider,
      source: email.provider
    ).call(message)

    Rails.logger.info("[MailInboundProcessJob] id=#{email.id} status=#{result.status}")
  end
end

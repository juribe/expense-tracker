# frozen_string_literal: true

module MailInbound
  # ContentPurger
  # One-off/controlled cleanup for email content stored before the jobs started
  # purging it. New deliveries and processed emails are purged at the end of
  # their lifecycle; this service is idempotent and safe to re-run.
  #
  # It only touches rows whose content is no longer needed:
  #   * handled deliveries;
  #   * failed deliveries older than RETRY_GRACE (their retries are over);
  #   * processed/ignored/needs_review emails;
  #   * failed emails older than RETRY_GRACE.
  #
  # Queued/processing rows and recent failures keep their content.
  #
  # Example: MailInbound::ContentPurger.new(dry_run: true).run
  class ContentPurger
    RETRY_GRACE = 1.day
    TERMINAL_PROCESSED_STATUSES = %w[processed ignored needs_review].freeze
    INBOUND_PROVIDERS = %w[cloudflare resend].freeze

    def initialize(dry_run: false)
      @dry_run = dry_run
    end

    def run
      counts = { deliveries: 0, processed_emails: 0 }

      MailInboundDelivery.find_each do |delivery|
        next unless purgeable_delivery?(delivery)

        counts[:deliveries] += 1
        delivery.purge_email_content! unless @dry_run
      end

      ProcessedEmail.where(provider: INBOUND_PROVIDERS).find_each do |email|
        next unless purgeable_processed_email?(email)

        counts[:processed_emails] += 1
        email.purge_email_content! unless @dry_run
      end

      counts
    end

    private

    def purgeable_delivery?(delivery)
      return false if delivery.raw_body.blank? && delivery.headers.blank? && delivery.params.blank?
      return true if delivery.status == "handled"

      delivery.status == "failed" && delivery.updated_at < RETRY_GRACE.ago
    end

    def purgeable_processed_email?(email)
      return false unless email.payload_data.key?("email")
      return true if email.status.in?(TERMINAL_PROCESSED_STATUSES)

      email.status == "failed" && email.updated_at < RETRY_GRACE.ago
    end
  end
end

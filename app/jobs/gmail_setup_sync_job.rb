# frozen_string_literal: true

# Background job for the explicit "Setup sync": scans the mailbox broadly
# for bank/financial emails (Gmail::SetupScanService) and persists Gmail
# criteria + money source suggestions. The job owns the same per-connection
# claim as GmailSyncJob, so a setup scan and a normal sync never overlap.
class GmailSetupSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id:)
    connection = GmailConnection.find_by(id: connection_id)
    return unless connection
    return unless connection.claim_sync!

    run_scan(connection)
  end

  private

  # Publishes the same UI contract as GmailSyncJob: clears the claim and stores
  # the summary when done, even on failure.
  def run_scan(connection)
    summary = Gmail::SetupScanService.call(connection)
    Rails.logger.info("[GmailSetupJob] connection=#{connection.id} #{summary.inspect}")
    connection.release_sync!(summary: summary)
  rescue StandardError => e
    Rails.logger.error("[GmailSetupJob] connection=#{connection.id} failed: #{e.class}: #{e.message}")
    connection.release_sync!(summary: { error: e.message })
  end
end

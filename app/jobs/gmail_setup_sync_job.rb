# frozen_string_literal: true

# Background job for the explicit "Setup sync": scans the mailbox broadly
# for bank/financial emails (Gmail::SetupScanService) and persists Gmail
# settings + money source suggestions. Mirrors GmailSyncJob's UI contract:
# sets `syncing` beforehand and clears it (storing the summary) when done,
# even on failure, so the settings page can poll sync_status.
class GmailSetupSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id:)
    connection = GmailConnection.find_by(id: connection_id)
    return unless connection
    # Another sync (normal or setup) already claimed this connection.
    return if connection.sync_running?

    connection.update!(syncing: Time.current)

    summary = Gmail::SetupScanService.call(connection)
    Rails.logger.info("[GmailSetupJob] connection=#{connection.id} #{summary.inspect}")
    connection.update!(last_sync_summary: summary, syncing: nil)
  rescue StandardError => e
    Rails.logger.error("[GmailSetupJob] connection=#{connection_id} failed: #{e.class}: #{e.message}")
    connection&.update!(last_sync_summary: { error: e.message }, syncing: nil)
  end
end

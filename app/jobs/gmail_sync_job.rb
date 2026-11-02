# frozen_string_literal: true

# Synchronizes ONE Gmail connection. GmailSyncDispatchJob fans out one job per
# active connection, and this job owns the per-connection claim so two runs can
# never sync the same mailbox at once.
class GmailSyncJob < ApplicationJob
  DEFAULT_INTERVAL_MINUTES = 15

  queue_as :default

  # Polling interval is configurable via ENV (documented in the settings UI).
  def self.polling_interval_minutes
    ENV.fetch("GMAIL_SYNC_INTERVAL_MINUTES", DEFAULT_INTERVAL_MINUTES).to_i.clamp(1, 1440)
  end

  def perform(connection_id:)
    connection = GmailConnection.find_by(id: connection_id)
    return unless connection
    # Never search a mailbox that has not been configured yet (no initial
    # setup sync, no saved criteria, no prior successful sync).
    return unless connection.search_configured?
    return unless connection.claim_sync!

    run_sync(connection)
  end

  private

  # Runs the sync for the claimed connection, publishing enough state on the
  # connection for the UI to poll: clears the claim and stores the summary when
  # done, even on failure.
  def run_sync(connection)
    summary = Gmail::SyncService.call(connection)
    Rails.logger.info("[GmailSyncJob] connection=#{connection.id} #{summary.inspect}")
    connection.release_sync!(summary: summary)
  rescue StandardError => e
    Rails.logger.error("[GmailSyncJob] connection=#{connection.id} failed: #{e.class}: #{e.message}")
    connection.release_sync!(summary: { error: e.message })
  end
end

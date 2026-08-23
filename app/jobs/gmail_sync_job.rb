# frozen_string_literal: true

# Periodic Gmail synchronization job. Schedule it (cron, Solid Queue
# recurring task...) at the interval defined by GMAIL_SYNC_INTERVAL_MINUTES.
class GmailSyncJob < ApplicationJob
  DEFAULT_INTERVAL_MINUTES = 15

  queue_as :default

  # Polling interval is configurable via ENV (documented in the settings UI).
  def self.polling_interval_minutes
    ENV.fetch("GMAIL_SYNC_INTERVAL_MINUTES", DEFAULT_INTERVAL_MINUTES).to_i.clamp(1, 1440)
  end

  def perform(connection_id: nil)
    scope = connection_id ? GmailConnection.where(id: connection_id) : GmailConnection.active

    scope.find_each do |connection|
      summary = Gmail::SyncService.call(connection)
      Rails.logger.info("[GmailSyncJob] connection=#{connection.id} #{summary.inspect}")
    rescue StandardError => e
      Rails.logger.error("[GmailSyncJob] connection=#{connection.id} failed: #{e.class}: #{e.message}")
    end
  end
end

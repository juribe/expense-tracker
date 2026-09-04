# frozen_string_literal: true

# Adds background-sync status fields to GmailConnection so the UI can poll
# and auto-refresh when an enqueued sync finishes, instead of the old
# synchronous request that blocked until the whole sync completed.
class AddSyncStateToGmailConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :gmail_connections, :syncing, :datetime
    add_column :gmail_connections, :last_sync_summary, :json
  end
end

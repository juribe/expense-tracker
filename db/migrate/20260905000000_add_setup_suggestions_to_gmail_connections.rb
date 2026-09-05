# frozen_string_literal: true

# Stores the aggregated Gmail-settings suggestions produced by an explicit
# Setup sync (Gmail::SetupScanService): suggested senders, domains and
# subject keywords with observation counts. Rendered by the setup page so
# the user confirms them into search_config instead of typing manually.
class AddSetupSuggestionsToGmailConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :gmail_connections, :setup_suggestions, :json
  end
end

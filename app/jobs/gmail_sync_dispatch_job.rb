# frozen_string_literal: true

# Recurring fan-out: enqueues one GmailSyncJob per active connection whose
# owner still has premium access, so each user's mailbox is synchronized in
# its own job, isolated from the rest.
class GmailSyncDispatchJob < ApplicationJob
  queue_as :default

  def perform
    connections = GmailConnection.active
    connections = connections.with_active_membership if PaymentEngine::Configuration.paid_access_required?

    connections.find_each do |connection|
      GmailSyncJob.perform_later(connection_id: connection.id)
    end
  end
end

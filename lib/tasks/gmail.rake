# frozen_string_literal: true

namespace :gmail do
  desc "Sync transaction emails for all active Gmail connections (interval: GMAIL_SYNC_INTERVAL_MINUTES)"
  task sync: :environment do
    puts "Polling interval: every #{GmailSyncJob.polling_interval_minutes} minutes " \
         "(configure with GMAIL_SYNC_INTERVAL_MINUTES)"
    GmailSyncJob.perform_now
    puts "Gmail sync finished."
  end
end

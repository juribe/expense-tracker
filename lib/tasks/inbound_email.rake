# frozen_string_literal: true

namespace :inbound_email do
  desc "Remove stored email content from finished inbound rows (DRY_RUN=1 previews)"
  task purge_content: :environment do
    dry_run = ENV.fetch("DRY_RUN", "0") == "1"
    counts = MailInbound::ContentPurger.new(dry_run: dry_run).run

    puts
    puts "Inbound email content purge#{' (DRY RUN - nothing written)' if dry_run}"
    puts "  deliveries cleaned        : #{counts[:deliveries]}"
    puts "  processed emails cleaned  : #{counts[:processed_emails]}"
    puts
  end
end

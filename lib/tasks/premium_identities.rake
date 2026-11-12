# frozen_string_literal: true

namespace :premium_identities do
  desc "Backfill premium identities from existing memberships and integrations"
  task backfill: :environment do
    counts = PremiumIdentities::Backfill.call
    puts "Premium identities processed: #{counts[:claimed]}, conflicts: #{counts[:conflicts]}"
    counts[:conflict_details].each { |detail| puts "Conflict: #{detail.inspect}" }
  end
end

# frozen_string_literal: true

# Protects memberships that existed before PremiumIdentity was introduced.
# Historical records are never removed by rolling back this migration.
class BackfillPremiumIdentities < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Backfilling premium identities from existing records" do
      counts = PremiumIdentities::Backfill.call
      say "Processed: #{counts[:claimed]}, conflicts: #{counts[:conflicts]}"
      counts[:conflict_details].each { |detail| say "Conflict: #{detail.inspect}" }
    end
  end

  def down
    # Premium identity history must survive rollbacks.
  end
end

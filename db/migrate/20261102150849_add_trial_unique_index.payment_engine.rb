class AddTrialUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :payment_engine_memberships, [:owner_type, :owner_id],
              unique: true,
              where: "source = 'trial'",
              name: "idx_pe_one_trial_per_owner"
  end
end

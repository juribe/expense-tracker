# frozen_string_literal: true

# Historical premium identities. Rows are intentionally independent from the
# user and from the membership: the foreign keys nullify instead of cascading,
# so deleting an account or a membership keeps the protection record.
class CreatePremiumIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :premium_identities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :identity_type, null: false
      t.string :fingerprint, null: false
      t.references :first_user, type: :uuid, null: true,
                                 foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :payment_engine_membership, type: :bigint, null: true,
                                               foreign_key: { to_table: :payment_engine_memberships, on_delete: :nullify }
      t.datetime :first_used_at, null: false
      t.datetime :released_at
      t.references :released_by_user, type: :uuid, null: true,
                                      foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :release_reason

      t.timestamps
    end

    add_index :premium_identities, :fingerprint, unique: true
    add_check_constraint :premium_identities,
                         "identity_type IN ('account_email', 'whatsapp', 'gmail', 'redirect_email')",
                         name: "premium_identities_identity_type_check"
  end
end

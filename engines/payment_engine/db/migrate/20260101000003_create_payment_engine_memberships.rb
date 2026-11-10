class CreatePaymentEngineMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_memberships do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.references :membership_type, null: false,
                   foreign_key: { to_table: :payment_engine_membership_types },
                   index: { name: "index_payment_engine_memberships_on_membership_type_id" }
      t.references :payment_option, null: true,
                   foreign_key: { to_table: :payment_engine_payment_options },
                   index: { name: "index_payment_engine_memberships_on_payment_option_id" }
      t.string :status, null: false, default: "pending"
      t.datetime :starts_at, null: false
      t.datetime :expires_at
      t.datetime :canceled_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_memberships, [ :owner_type, :owner_id ]
    add_index :payment_engine_memberships, [ :owner_type, :owner_id, :membership_type_id, :status ],
              name: "index_payment_engine_memberships_owner_type_status"
    add_index :payment_engine_memberships, [ :owner_type, :owner_id, :membership_type_id ],
              unique: true,
              where: "status IN ('active', 'trialing')",
              name: "index_payment_engine_memberships_unique_open_access"
    add_index :payment_engine_memberships, [ :status, :expires_at ]
    add_check_constraint :payment_engine_memberships,
                         "status IN ('pending', 'trialing', 'active', 'expired', 'canceled')",
                         name: "memberships_status_valid"
  end
end

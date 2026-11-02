# This migration comes from payment_engine (originally 20261102000100)
class CreatePaymentEngineMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_memberships do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.references :membership_type, null: false, foreign_key: { to_table: :payment_engine_membership_types }
      t.string :status, null: false, default: "active"
      t.datetime :starts_at
      t.datetime :expires_at
      t.string :source, default: "manual"
      t.bigint :purchase_id
      t.bigint :subscription_id
      t.timestamps
    end
    add_index :payment_engine_memberships, [:owner_type, :owner_id]
  end
end

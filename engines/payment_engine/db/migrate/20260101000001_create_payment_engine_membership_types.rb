class CreatePaymentEngineMembershipTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_membership_types do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_membership_types, :slug, unique: true
    add_index :payment_engine_membership_types, :active
  end
end

class CreatePaymentEngineMembershipTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_membership_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.integer :position, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :payment_engine_membership_types, :code, unique: true
  end
end

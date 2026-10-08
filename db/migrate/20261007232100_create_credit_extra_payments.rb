class CreateCreditExtraPayments < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_extra_payments do |t|
      t.references :money_source, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :application_type, null: false
      t.decimal :principal_reduction, precision: 14, scale: 2, default: "0.0", null: false
      t.integer :installments_affected
      t.jsonb :effect, null: false, default: {}
      t.string :note

      t.timestamps
    end

    add_index :credit_extra_payments, [ :money_source_id, :date ]
  end
end

class CreatePaymentEnginePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_payments do |t|
      t.references :purchase, null: true, foreign_key: { to_table: :payment_engine_purchases }
      t.string :provider_code
      t.string :external_reference
      t.decimal :amount, precision: 15, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: "COP"
      t.string :status, null: false, default: "pending"
      t.string :payment_method
      t.text :error_message
      t.timestamps
    end
  end
end

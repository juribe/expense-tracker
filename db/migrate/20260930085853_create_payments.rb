# frozen_string_literal: true

class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :user, null: false
      t.references :expense, null: false, foreign_key: { to_table: :transactions }
      t.references :money_source, null: false
      t.date :date, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.decimal :principal_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :interest_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :insurance_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :other_amount, precision: 14, scale: 2, null: false, default: 0
      t.string :source, default: "manual", null: false

      t.timestamps
    end

    add_index :payments, [ :expense_id, :money_source_id ],
              unique: true, name: "index_payments_on_expense_and_target"
  end
end

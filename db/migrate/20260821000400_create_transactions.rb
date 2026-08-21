# frozen_string_literal: true

class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.string :kind, null: false
      t.string :description
      t.string :source, null: false, default: "manual"
      t.references :recurring_template, foreign_key: true
      t.timestamps
    end

    add_index :transactions, :kind
    add_index :transactions, :date
    add_index :transactions, [ :user_id, :kind, :date ]
  end
end

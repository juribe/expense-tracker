# frozen_string_literal: true

class CreateTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :transfers do |t|
      t.references :user, null: false, foreign_key: true
      t.references :from_source, null: false, foreign_key: { to_table: :money_sources }
      t.references :to_source, null: false, foreign_key: { to_table: :money_sources }
      t.decimal :amount, null: false, precision: 12, scale: 2
      t.date :date, null: false
      t.string :note
      t.timestamps
    end

    add_index :transfers, [ :user_id, :date ]
  end
end

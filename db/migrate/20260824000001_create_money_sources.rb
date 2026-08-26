# frozen_string_literal: true

class CreateMoneySources < ActiveRecord::Migration[8.0]
  def change
    create_table :money_sources do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :bank
      t.references :parent, foreign_key: { to_table: :money_sources }
      t.decimal :starting_balance, precision: 12, scale: 2, default: 0, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :money_sources, [ :user_id, :kind ]
  end
end

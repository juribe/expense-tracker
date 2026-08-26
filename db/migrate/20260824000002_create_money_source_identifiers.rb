# frozen_string_literal: true

class CreateMoneySourceIdentifiers < ActiveRecord::Migration[8.0]
  def change
    create_table :money_source_identifiers do |t|
      t.references :money_source, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :value, null: false
      t.timestamps
    end

    add_index :money_source_identifiers, [ :kind, :value ], unique: true
    add_index :money_source_identifiers, [ :money_source_id, :kind ]
  end
end

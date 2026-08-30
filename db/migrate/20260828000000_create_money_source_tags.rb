# frozen_string_literal: true

class CreateMoneySourceTags < ActiveRecord::Migration[8.0]
  def change
    create_table :money_source_tags do |t|
      t.references :money_source, null: false, foreign_key: true
      t.string :value, null: false
      t.timestamps
    end

    add_index :money_source_tags, [ :money_source_id, :value ], unique: true
  end
end
# frozen_string_literal: true

class CreateGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :target_amount, precision: 14, scale: 2, null: false
      t.decimal :saved_amount, precision: 14, scale: 2, null: false, default: 0
      t.date :target_date

      t.timestamps
    end

    add_index :goals, [ :user_id, :name ]
  end
end

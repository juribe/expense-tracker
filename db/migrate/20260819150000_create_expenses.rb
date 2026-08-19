# frozen_string_literal: true

class CreateExpenses < ActiveRecord::Migration[8.0]
  def change
    create_table :expenses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.string :description
      t.date :date, null: false
      t.string :frequency, default: 'one_time'
      t.timestamps
    end
  end
end

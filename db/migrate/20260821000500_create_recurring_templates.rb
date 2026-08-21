# frozen_string_literal: true

class CreateRecurringTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_templates do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :kind, null: false
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.string :description
      t.integer :payment_day
      t.string :frequency, null: false, default: "monthly"
      t.boolean :active, null: false, default: true
      t.string :source, null: false, default: "manual"
      t.timestamps
    end

    add_index :recurring_templates, :kind
    add_index :recurring_templates, [ :user_id, :kind ]
  end
end

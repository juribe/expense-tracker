# frozen_string_literal: true

class CreateExpenseCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :expense_candidates do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2
      t.date :date
      t.string :description
      t.references :category, foreign_key: true
      t.references :money_source, foreign_key: true
      t.string :status, null: false, default: "needs_review"
      t.string :source, null: false, default: "text"
      t.float :confidence
      t.jsonb :missing_fields, default: [], null: false
      t.text :original_input
      t.text :original_text
      t.references :expense, foreign_key: { to_table: :transactions }
      t.jsonb :metadata, default: {}, null: false
      t.datetime :confirmed_at
      t.datetime :discarded_at
      t.timestamps

      t.index [:user_id, :status]
      t.index [:user_id, :created_at]
    end
  end
end

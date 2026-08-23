# frozen_string_literal: true

class CreateProcessedEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_emails do |t|
      t.references :user, null: false, foreign_key: true
      t.references :expense, foreign_key: { to_table: :transactions }

      t.string :provider, null: false, default: "gmail"
      t.string :message_id, null: false
      t.string :status, null: false, default: "processed"

      # Extracted transactions kept for the review queue / debugging.
      t.text :payload
      t.string :failure_reason
      t.integer :attempts, null: false, default: 0

      t.datetime :processed_at

      t.timestamps
    end

    add_index :processed_emails, [:provider, :message_id], unique: true
    add_index :processed_emails, :status
  end
end

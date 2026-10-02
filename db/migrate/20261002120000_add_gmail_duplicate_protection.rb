# frozen_string_literal: true

# Database-level gmail duplicate protection:
#
# Partial unique index on transactions (user_id, gmail_message_id, amount,
# date) for gmail expenses: the database itself rejects a second expense
# created from the same email, even when application-level checks race.
class AddGmailDuplicateProtection < ActiveRecord::Migration[8.0]
  def change
    add_index :transactions,
              [ :user_id, :gmail_message_id, :amount, :date ],
              unique: true,
              where: "gmail_message_id IS NOT NULL",
              name: "index_transactions_gmail_dedup"
  end
end

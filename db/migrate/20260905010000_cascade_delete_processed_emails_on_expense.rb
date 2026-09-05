# frozen_string_literal: true

class CascadeDeleteProcessedEmailsOnExpense < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :processed_emails, :transactions, column: :expense_id
    add_foreign_key :processed_emails, :transactions, column: :expense_id, on_delete: :cascade
  end
end
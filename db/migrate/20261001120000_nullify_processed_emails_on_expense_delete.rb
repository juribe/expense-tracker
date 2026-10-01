# frozen_string_literal: true

class NullifyProcessedEmailsOnExpenseDelete < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :processed_emails, column: :expense_id
    add_foreign_key :processed_emails, :transactions, column: :expense_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :processed_emails, column: :expense_id
    add_foreign_key :processed_emails, :transactions, column: :expense_id, on_delete: :cascade
  end
end

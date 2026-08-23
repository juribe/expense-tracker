# frozen_string_literal: true

class AddGmailMessageIdToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :gmail_message_id, :string
    add_index :transactions, :gmail_message_id
  end
end

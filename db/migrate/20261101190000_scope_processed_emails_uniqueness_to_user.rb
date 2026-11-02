# frozen_string_literal: true

class ScopeProcessedEmailsUniquenessToUser < ActiveRecord::Migration[8.1]
  def change
    remove_index :processed_emails, columns: [ :provider, :message_id ],
                 name: "index_processed_emails_on_provider_and_message_id"
    add_index :processed_emails, [ :user_id, :provider, :message_id ], unique: true,
              name: "index_processed_emails_on_user_provider_message_id"
  end
end

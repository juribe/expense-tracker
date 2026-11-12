class AddUniqueIndexToPendingWhatsappConnections < ActiveRecord::Migration[8.1]
  def change
    remove_index :pending_whatsapp_connections, :token_digest
    add_index :pending_whatsapp_connections, :token_digest, unique: true
  end
end

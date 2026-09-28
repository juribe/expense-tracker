class AddWhatsappNumberToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :whatsapp_number, :string
    add_index :users, :whatsapp_number, unique: true
  end
end

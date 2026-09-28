class CreateWhatsappLinkingTables < ActiveRecord::Migration[8.0]
  def up
    create_table :whatsapp_identities do |t|
      t.string   :phone_number, null: false
      t.references :claimed_by_user, foreign_key: { to_table: :users }, index: false
      t.datetime :claimed_at
      t.timestamps
    end
    add_index :whatsapp_identities, :phone_number, unique: true
    add_index :whatsapp_identities, :claimed_by_user_id

    create_table :whatsapp_connections do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :whatsapp_identity, null: false, foreign_key: true, index: false
      t.datetime :connected_at
      t.datetime :disconnected_at
      t.timestamps
    end
    add_index :whatsapp_connections, :user_id
    add_index :whatsapp_connections, :whatsapp_identity_id,
              unique: true,
              where: "disconnected_at IS NULL",
              name: "index_whatsapp_connections_on_identity_active"

    create_table :pending_whatsapp_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :pending_whatsapp_connections, :token_digest

    # Backfill: connections created before this feature used users.whatsapp_number.
    User.where.not(whatsapp_number: [ nil, "" ]).find_each do |user|
      normalized = user.whatsapp_number.gsub(/\D/, "")
      identity = WhatsappIdentity.find_or_create_by!(phone_number: normalized) do |i|
        i.claimed_by_user_id = user.id
        i.claimed_at = Time.current
      end
      unless WhatsappConnection.active.exists?(whatsapp_identity_id: identity.id)
        WhatsappConnection.create!(user: user, whatsapp_identity: identity, connected_at: Time.current)
      end
    end

    remove_column :users, :whatsapp_number
  end

  def down
    add_column :users, :whatsapp_number, :string
    WhatsappConnection.active.includes(:whatsapp_identity).find_each do |connection|
      next if connection.whatsapp_identity.blank?
      User.where(id: connection.user_id).update_all(whatsapp_number: connection.whatsapp_identity.phone_number)
    end

    drop_table :pending_whatsapp_connections
    drop_table :whatsapp_connections
    drop_table :whatsapp_identities
  end
end

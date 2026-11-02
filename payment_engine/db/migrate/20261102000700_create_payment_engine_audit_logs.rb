class CreatePaymentEngineAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_engine_audit_logs do |t|
      t.string :actor_type
      t.string :actor_id
      t.string :action, null: false
      t.string :auditable_type
      t.string :auditable_id
      t.text :reason
      t.jsonb :changes, default: {}
      t.jsonb :metadata, default: {}
      t.datetime :created_at, null: false
    end
    add_index :payment_engine_audit_logs, [:auditable_type, :auditable_id]
  end
end

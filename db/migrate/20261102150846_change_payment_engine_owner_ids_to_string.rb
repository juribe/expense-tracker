class ChangePaymentEngineOwnerIdsToString < ActiveRecord::Migration[8.1]
  def up
    change_column :payment_engine_memberships, :owner_id, :string
    change_column :payment_engine_purchases, :owner_id, :string
    change_column :payment_engine_subscriptions, :owner_id, :string
    change_column :payment_engine_provider_customers, :owner_id, :string
    change_column :payment_engine_audit_logs, :actor_id, :string
    change_column :payment_engine_audit_logs, :auditable_id, :string
  end
  def down
    change_column :payment_engine_memberships, :owner_id, :bigint
    change_column :payment_engine_purchases, :owner_id, :bigint
    change_column :payment_engine_subscriptions, :owner_id, :bigint
    change_column :payment_engine_provider_customers, :owner_id, :bigint
    change_column :payment_engine_audit_logs, :actor_id, :bigint
    change_column :payment_engine_audit_logs, :auditable_id, :bigint
  end
end

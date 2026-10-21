class AddIdempotencyKeyToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :idempotency_key, :uuid
    add_index :transactions, :idempotency_key, unique: true
  end
end

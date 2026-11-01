# frozen_string_literal: true

class AddGmfMetadataToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :gmf_origin_type, :string
    add_column :transactions, :gmf_origin_id, :uuid
    add_column :transactions, :gmf_status, :string
    add_column :transactions, :gmf_estimated, :boolean, default: false, null: false
    add_column :transactions, :gmf_bank_reference, :string
    add_index :transactions, [:user_id, :gmf_origin_type, :gmf_origin_id],
              name: "index_transactions_gmf_origin"
  end
end

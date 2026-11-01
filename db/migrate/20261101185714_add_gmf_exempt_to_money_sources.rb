# frozen_string_literal: true

class AddGmfExemptToMoneySources < ActiveRecord::Migration[8.1]
  def change
    add_column :money_sources, :gmf_exempt, :boolean, null: false, default: false
    add_index :money_sources, :user_id, unique: true, where: "gmf_exempt = true", name: "index_money_sources_gmf_exempt_per_user"
  end
end

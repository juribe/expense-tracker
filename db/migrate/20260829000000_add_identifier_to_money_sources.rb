# frozen_string_literal: true

class AddIdentifierToMoneySources < ActiveRecord::Migration[8.0]
  def change
    add_column :money_sources, :identifier, :string
    add_index :money_sources, [:user_id, :identifier], unique: true, name: "index_money_sources_on_user_id_and_identifier"
  end
end
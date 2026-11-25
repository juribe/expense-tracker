# frozen_string_literal: true

class AddDeletedAtToMoneySources < ActiveRecord::Migration[8.1]
  def change
    add_column :money_sources, :deleted_at, :datetime
    add_index :money_sources, :deleted_at
  end
end

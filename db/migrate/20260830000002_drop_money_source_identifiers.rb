# frozen_string_literal: true

class DropMoneySourceIdentifiers < ActiveRecord::Migration[8.0]
  # MoneySourceIdentifier has been replaced by MoneySourceTag; its data was
  # migrated into money_source_tags beforehand.
  def change
    drop_table :money_source_identifiers
  end
end
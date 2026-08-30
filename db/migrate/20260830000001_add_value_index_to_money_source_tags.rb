# frozen_string_literal: true

class AddValueIndexToMoneySourceTags < ActiveRecord::Migration[8.0]
  def change
    add_index :money_source_tags, :value
  end
end
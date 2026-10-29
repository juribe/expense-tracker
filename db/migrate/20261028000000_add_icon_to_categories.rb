# frozen_string_literal: true

class AddIconToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :icon, :string
  end
end
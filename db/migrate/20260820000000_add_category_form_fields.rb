# frozen_string_literal: true

class AddCategoryFormFields < ActiveRecord::Migration[8.0]
  def change
    change_table :categories do |t|
      t.string :slug, null: false
      t.bigint :parent_id
      t.boolean :active, null: false, default: true
      t.string :image
    end

    add_index :categories, :slug, unique: true
    add_index :categories, :parent_id
  end
end
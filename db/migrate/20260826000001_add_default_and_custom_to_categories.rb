# frozen_string_literal: true

class AddDefaultAndCustomToCategories < ActiveRecord::Migration[8.0]
  def change
    change_table :categories do |t|
      t.bigint :user_id, null: true
      t.boolean :is_default, null: false, default: false
      t.string :category_type, null: true
    end

    add_index :categories, :user_id
    add_index :categories, :is_default
    add_index :categories, :category_type
    add_foreign_key :categories, :users
  end
end

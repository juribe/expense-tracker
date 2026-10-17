# frozen_string_literal: true

class UpdateCategoriesRemoveSlugImageAddTags < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :tags, :jsonb, default: [], null: false

    remove_index :categories, :slug if index_exists?(:categories, :slug)
    remove_column :categories, :slug, :string
    remove_column :categories, :image, :string
  end
end

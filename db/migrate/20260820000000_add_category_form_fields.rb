# frozen_string_literal: true

class AddCategoryFormFields < ActiveRecord::Migration[8.0]
  def up
    # Add columns without NOT NULL so existing rows are not rejected
    change_table :categories do |t|
      t.string :slug
      t.bigint :parent_id
      t.boolean :active, null: false, default: true
      t.string :image
    end

    # Backfill slugs for existing rows (name -> slug)
    execute <<~SQL
      UPDATE categories
      SET slug = CASE
        WHEN name IS NULL OR TRIM(name) = '' THEN 'category-' || id
        ELSE lower(replace(trim(name), ' ', '-'))
      END
      WHERE slug IS NULL OR slug = ''
    SQL

    # Now safe to enforce NOT NULL and uniqueness
    change_column_null :categories, :slug, false
    add_index :categories, :slug, unique: true
    add_index :categories, :parent_id
  end

  def down
    remove_index :categories, :parent_id
    remove_index :categories, :slug
    remove_column :categories, :image
    remove_column :categories, :active
    remove_column :categories, :parent_id
    remove_column :categories, :slug
  end
end
# frozen_string_literal: true

# Derived read models for the Maglev-backed help center. Maglev pages remain
# the source of truth; these tables only project published content for
# listings, counts, ordering and search.
class CreateHelpCenterIndices < ActiveRecord::Migration[8.1]
  def change
    create_table :help_category_indices, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :maglev_page, type: :uuid, null: false,
                                 foreign_key: { to_table: :maglev_pages, on_delete: :cascade },
                                 index: { unique: true }
      t.string :locale, null: false, default: "es"
      t.string :path, null: false
      t.string :name, null: false
      t.text :description
      t.string :icon
      t.string :image_url
      t.integer :position, null: false, default: 100
      t.datetime :published_at
      t.datetime :page_updated_at
      t.string :seo_title
      t.string :meta_description
      t.timestamps
    end

    add_index :help_category_indices, [ :locale, :path ], unique: true
    add_index :help_category_indices, [ :locale, :position ]

    create_table :help_article_indices, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :maglev_page, type: :uuid, null: false,
                                 foreign_key: { to_table: :maglev_pages, on_delete: :cascade },
                                 index: { unique: true }
      t.string :locale, null: false, default: "es"
      t.string :path, null: false
      t.string :category_path, null: false
      t.string :category_name, null: false
      t.string :title, null: false
      t.text :summary
      t.text :search_text, null: false
      t.string :normalized_title, null: false
      t.string :normalized_summary
      t.string :icon
      t.string :cover_image_url
      t.integer :position, null: false, default: 100
      t.boolean :featured, null: false, default: false
      t.boolean :popular, null: false, default: false
      t.datetime :published_at
      t.datetime :page_updated_at
      t.string :seo_title
      t.string :meta_description
      t.timestamps
    end

    add_index :help_article_indices, [ :locale, :path ], unique: true
    add_index :help_article_indices, [ :locale, :category_path, :position ]
    add_index :help_article_indices, :search_text, using: :gin, opclass: :gin_trgm_ops
    add_index :help_article_indices, :normalized_title, using: :gin, opclass: :gin_trgm_ops
  end
end

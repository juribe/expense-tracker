# frozen_string_literal: true

# Cache of resolved activity → category knowledge so repeated merchants reuse
# the same classification without a new AI request. User corrections always
# win (source = "user"); the row is keyed by the normalized activity name.
class CreateActivityClassifications < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_classifications do |t|
      t.bigint :user_id, null: false
      t.string :normalized_name, null: false
      t.string :original_name
      t.bigint :category_id
      t.string :subcategory
      t.decimal :confidence, precision: 4, scale: 3
      t.string :source, null: false, default: "ai"
      t.timestamps
    end

    add_index :activity_classifications, [ :user_id, :normalized_name ], unique: true
    add_index :activity_classifications, :category_id
    add_foreign_key :activity_classifications, :users
    add_foreign_key :activity_classifications, :categories
  end
end

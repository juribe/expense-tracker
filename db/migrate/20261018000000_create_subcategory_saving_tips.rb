# frozen_string_literal: true

class CreateSubcategorySavingTips < ActiveRecord::Migration[8.0]
  def change
    create_table :subcategory_saving_tips, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :subcategory, type: :uuid, null: false, foreign_key: { to_table: :categories }
      t.string :title, null: false
      t.text :body, null: false
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :subcategory_saving_tips, [ :subcategory_id, :position ], name: "index_subcategory_saving_tips_on_subcategory_and_position"
    add_index :subcategory_saving_tips, [ :subcategory_id, :active ], name: "index_subcategory_saving_tips_on_subcategory_and_active"
  end
end

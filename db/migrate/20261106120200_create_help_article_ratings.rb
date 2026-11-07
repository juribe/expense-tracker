# frozen_string_literal: true

# Anonymous or authenticated article feedback. No raw IPs are stored; the
# fingerprint is a digest scoped to the article and visitor.
class CreateHelpArticleRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :help_article_ratings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :maglev_page_id, null: false
      t.boolean :helpful, null: false
      t.string :fingerprint, null: false
      t.timestamps
    end

    add_foreign_key :help_article_ratings, :maglev_pages, column: :maglev_page_id, on_delete: :cascade
    add_index :help_article_ratings, [ :maglev_page_id, :fingerprint ], unique: true
  end
end

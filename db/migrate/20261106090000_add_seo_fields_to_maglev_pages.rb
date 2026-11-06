# Adds the extra SEO fields (canonical URL and meta robots) that Maglev CMS v3
# does not provide natively but the marketing site needs.
class AddSeoFieldsToMaglevPages < ActiveRecord::Migration[8.0]
  def change
    add_column :maglev_pages, :canonical_url_translations, :jsonb, default: {}
    add_column :maglev_pages, :meta_robots_translations, :jsonb, default: {}
  end
end

# HelpArticleRating
# Anonymous or authenticated feedback for a published help article.
#
# Associations: belongs_to :maglev_page
# Methods: record!
#
# Example: HelpArticleRating.record!(maglev_page_id: page.id, fingerprint: "anon:...", helpful: true)
class HelpArticleRating < ApplicationRecord
  belongs_to :maglev_page, class_name: "Maglev::Page", inverse_of: false

  validates :maglev_page_id, presence: true
  validates :fingerprint, presence: true, uniqueness: { scope: :maglev_page_id }
  validates :helpful, inclusion: { in: [ true, false ] }

  def self.record!(maglev_page_id:, fingerprint:, helpful:)
    find_by(maglev_page_id: maglev_page_id, fingerprint: fingerprint) ||
      create!(maglev_page_id: maglev_page_id, fingerprint: fingerprint, helpful: helpful)
  rescue ActiveRecord::RecordNotUnique
    find_by!(maglev_page_id: maglev_page_id, fingerprint: fingerprint)
  end
end

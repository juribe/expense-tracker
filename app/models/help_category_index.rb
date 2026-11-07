# HelpCategoryIndex
# Derived, rebuildable read model for published help categories.
#
# Associations: belongs_to :maglev_page
# Scopes: for_locale, ordered
#
# Example: HelpCategoryIndex.ordered.map(&:url)
class HelpCategoryIndex < ApplicationRecord
  belongs_to :maglev_page, class_name: "Maglev::Page", inverse_of: false

  validates :maglev_page_id, presence: true, uniqueness: true
  validates :locale, :path, :name, presence: true
  validates :path, uniqueness: { scope: :locale }

  scope :for_locale, ->(locale) { where(locale: locale) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  def url
    "/#{path}"
  end
end

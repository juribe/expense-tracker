# HelpArticleIndex
# Derived, rebuildable read model for published help articles.
#
# Associations: belongs_to :maglev_page
# Scopes: for_locale, in_category, ordered, popular
#
# Example: HelpArticleIndex.in_category("ayuda/gastos").ordered
class HelpArticleIndex < ApplicationRecord
  belongs_to :maglev_page, class_name: "Maglev::Page", inverse_of: false

  validates :maglev_page_id, presence: true, uniqueness: true
  validates :locale, :path, :category_path, :category_name, :title, :search_text,
            :normalized_title, presence: true
  validates :path, uniqueness: { scope: :locale }

  scope :for_locale, ->(locale) { where(locale: locale) }
  scope :in_category, ->(path) { where(category_path: path) }
  scope :ordered, -> { order(position: :asc, title: :asc) }
  scope :popular, -> { where(popular: true) }

  def url
    "/#{path}"
  end
end

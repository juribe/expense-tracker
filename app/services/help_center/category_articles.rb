# HelpCenter::CategoryArticles
# Paginates published articles belonging to a category.
class HelpCenter::CategoryArticles
  PER_PAGE = 8

  def initialize(category_path:, page: nil, per_page: PER_PAGE)
    @category_path = category_path
    @page = page.presence || 1
    @per_page = per_page
  end

  def call
    HelpArticleIndex
      .for_locale(HelpCenter::LOCALE)
      .in_category(@category_path)
      .ordered
      .paginate(page: @page, per_page: @per_page)
  end
end

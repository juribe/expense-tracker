# HelpCenter::PopularArticles
# Returns popular help articles, falling back to the latest ordered articles.
class HelpCenter::PopularArticles
  def initialize(limit: 5)
    @limit = limit
  end

  def call
    base = HelpArticleIndex
           .for_locale(HelpCenter::LOCALE)
           .where(category_path: HelpCategoryIndex.for_locale(HelpCenter::LOCALE).select(:path))
           .ordered

    popular = base.popular.limit(@limit)
    popular.exists? ? popular : base.limit(@limit)
  end
end

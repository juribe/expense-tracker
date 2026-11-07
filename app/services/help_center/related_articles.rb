# HelpCenter::RelatedArticles
# Resolves editor-provided related paths, falling back to the same category.
class HelpCenter::RelatedArticles
  def initialize(article:, paths: [], limit: 3)
    @article = article
    @paths = Array(paths).map(&:strip).reject(&:blank?)
    @limit = limit
  end

  def call
    return HelpArticleIndex.none if @article.nil?

    if @paths.any?
      HelpArticleIndex
        .for_locale(HelpCenter::LOCALE)
        .where(path: @paths)
        .where.not(id: @article.id)
        .ordered
        .limit(@limit)
    else
      HelpArticleIndex
        .for_locale(HelpCenter::LOCALE)
        .in_category(@article.category_path)
        .where.not(id: @article.id)
        .ordered
        .limit(@limit)
    end
  end
end

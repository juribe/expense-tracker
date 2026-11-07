# HelpCenter::CategoryDirectory
# Returns published categories with their article counts for cards and lists.
class HelpCenter::CategoryDirectory
  Entry = Struct.new(:category, :article_count, keyword_init: true)

  def call
    categories = HelpCategoryIndex.for_locale(HelpCenter::LOCALE).ordered.to_a
    counts = HelpArticleIndex
             .for_locale(HelpCenter::LOCALE)
             .where(category_path: categories.map(&:path))
             .group(:category_path)
             .count

    categories.map do |category|
      Entry.new(category: category, article_count: counts.fetch(category.path, 0))
    end
  end
end

# HelpCenter::Search
# Finds published help articles by normalized title, summary and body text.
#
# Example: HelpCenter::Search.new(query: "registrar gasto").call
class HelpCenter::Search
  DEFAULT_LIMIT = 20

  def initialize(query:, locale: HelpCenter::LOCALE, limit: DEFAULT_LIMIT)
    @query = query.to_s
    @locale = locale
    @limit = normalize_limit(limit)
  end

  def call
    return HelpArticleIndex.none if terms.empty?

    terms.reduce(base_scope) do |scope, term|
      scope.where("help_article_indices.search_text LIKE ?", "%#{escaped(term)}%")
    end.order(Arel.sql(ranking_sql)).order(:position, :title).limit(@limit)
  end

  private

  def terms
    @terms ||= HelpCenter::TextNormalizer.call(@query).split
  end

  def base_scope
    HelpArticleIndex
      .for_locale(@locale)
      .where(category_path: HelpCategoryIndex.for_locale(@locale).select(:path))
  end

  def ranking_sql
    phrase = quote(terms.join(" "))
    prefix = quote("#{escaped(terms.join(' '))}%")

    <<~SQL.squish
      CASE
        WHEN normalized_title = #{phrase} THEN 0
        WHEN #{all_terms_clause('normalized_title')} THEN 1
        WHEN normalized_title LIKE #{prefix} THEN 2
        WHEN #{all_terms_clause('normalized_summary')} THEN 3
        ELSE 4
      END
    SQL
  end

  def all_terms_clause(column)
    terms.map do |term|
      "#{column} LIKE #{quote("%#{escaped(term)}%")}"
    end.join(" AND ")
  end

  def escaped(value)
    ActiveRecord::Base.sanitize_sql_like(value)
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end

  def normalize_limit(limit)
    value = limit.to_i
    value.positive? ? value : DEFAULT_LIMIT
  end
end

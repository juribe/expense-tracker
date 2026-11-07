# HelpCenterHelper
# Presentation helpers for the Maglev help center pages.
#
# Example: help_center_breadcrumbs(maglev_page)
module HelpCenterHelper
  HELP_HTML_TAGS = %w[
    p br strong em b i u a ul ol li h2 h3 h4 blockquote code pre
    table thead tbody tr th td hr span
  ].freeze
  HELP_HTML_ATTRIBUTES = %w[href title target rel].freeze

  def help_center_page?(page)
    HelpCenter::PagePath.new(page.path).help_center?
  end

  def help_center_article_page?(page)
    HelpCenter::PagePath.new(page.path).article?
  end

  def help_center_article_index(page = maglev_page)
    @help_center_article_indexes ||= {}
    @help_center_article_indexes[page.id] ||= HelpArticleIndex.find_by(
      maglev_page_id: page.id,
      locale: HelpCenter::LOCALE
    )
  end

  def help_center_category_index(page = maglev_page)
    @help_center_category_indexes ||= {}
    @help_center_category_indexes[page.id] ||= HelpCategoryIndex.find_by(
      maglev_page_id: page.id,
      locale: HelpCenter::LOCALE
    )
  end

  def help_center_breadcrumbs(page)
    path = HelpCenter::PagePath.new(page.path)
    items = [ { label: "Centro de ayuda", url: path.root? ? nil : "/ayuda" } ]

    if path.category?
      items << { label: help_center_category_index(page)&.name.presence || page.title, url: nil }
    elsif path.article?
      category = HelpCategoryIndex.find_by(locale: HelpCenter::LOCALE, path: path.category_path)
      items << { label: category&.name.presence || path.category_path.to_s.split("/").last.to_s.humanize,
                 url: "/#{path.category_path}" }
      items << { label: page.title, url: nil }
    end

    items
  end

  def help_center_date(value)
    return if value.blank?

    l(value.to_date, format: :long)
  end

  def help_sanitize_html(value)
    sanitize(value.to_s, tags: HELP_HTML_TAGS, attributes: HELP_HTML_ATTRIBUTES)
  end

  def help_sanitize_inline(value)
    sanitize(value.to_s, tags: %w[br strong em b i u a], attributes: %w[href title target rel])
  end

  def help_center_related_paths(value)
    value.to_s.lines.map(&:strip).reject(&:blank?)
  end

  def help_safe_external_url(value)
    uri = URI.parse(value.to_s)
    uri if %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    nil
  end

  def help_center_seo_data(page, site:, base_url:)
    path = HelpCenter::PagePath.new(page.path)
    return [] unless path.help_center?

    organization = {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => site.name.presence || "Yogasto",
      "url" => base_url,
      "logo" => "#{base_url}/brand/yogasto-logo-claro.svg"
    }

    breadcrumbs = {
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => help_center_breadcrumbs(page).each_with_index.map do |item, index|
        {
          "@type" => "ListItem",
          "position" => index + 1,
          "name" => item[:label],
          "item" => item[:url] ? "#{base_url}#{item[:url]}" : "#{base_url}/#{page.path}"
        }
      end
    }

    [ organization, breadcrumbs, help_center_article_seo(page, site: site, base_url: base_url) ].compact
  end

  private

  def help_center_article_seo(page, site:, base_url:)
    return unless HelpCenter::PagePath.new(page.path).article?

    article = help_center_article_index(page)

    {
      "@context" => "https://schema.org",
      "@type" => "TechArticle",
      "headline" => page.title,
      "description" => page.meta_description,
      "datePublished" => (article&.published_at || page.published_at)&.iso8601,
      "dateModified" => (article&.published_at || page.published_at || page.updated_at)&.iso8601,
      "mainEntityOfPage" => "#{base_url}/#{page.path}",
      "author" => { "@type" => "Organization", "name" => site.name.presence || "Yogasto" },
      "publisher" => { "@type" => "Organization", "name" => site.name.presence || "Yogasto" }
    }.compact
  end
end

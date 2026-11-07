# HelpCenter::Indexer
# Projects a published Maglev help page into the derived read models.
#
# Example: HelpCenter::Indexer.new(maglev_page).call
class HelpCenter::Indexer
  STRUCTURAL_KEYS = %w[id type parent_id].freeze
  NON_TEXT_KEYS = %w[
    image logo cover_image cover_image_url image_url icon href link cta
    background url level variant position related_paths search_placeholder
    search_hint search_button_label clear_label
  ].freeze
  URL_PATTERN = %r{\A(?:https?:)?//}i

  def initialize(page)
    @page = page
    @locale = HelpCenter::LOCALE
  end

  def call
    path = HelpCenter::PagePath.new(page_path)

    return delete_index unless path.valid? && published_and_visible?
    return index_category(path) if path.category?
    return index_article(path) if path.article?

    delete_index
  end

  private

  attr_reader :page, :locale

  def page_path
    page.path_hash[locale].to_s
  end

  def published_and_visible?
    page.visible? && page.published?
  end

  def index_category(path)
    settings = section_settings("help_category_header")
    category = HelpCategoryIndex.find_or_initialize_by(maglev_page_id: page.id)

    category.assign_attributes(
      locale: locale,
      path: path.to_s,
      name: title,
      description: settings["description"].presence || meta_description,
      icon: settings["icon"].presence,
      image_url: image_url(settings["image"]),
      position: position_from(settings["position"]),
      published_at: page.published_at,
      page_updated_at: page.updated_at,
      seo_title: seo_title,
      meta_description: meta_description
    )
    category.save!

    HelpArticleIndex.where(locale: locale, category_path: path.to_s)
                    .update_all(category_name: category.name, updated_at: Time.current)
    category
  end

  def index_article(path)
    settings = section_settings("help_article_header")
    summary = settings["summary"].presence || meta_description
    article = HelpArticleIndex.find_or_initialize_by(maglev_page_id: page.id)

    article.assign_attributes(
      locale: locale,
      path: path.to_s,
      category_path: path.category_path,
      category_name: category_name_for(path),
      title: title,
      summary: summary,
      search_text: search_text(title, summary),
      normalized_title: HelpCenter::TextNormalizer.call(title),
      normalized_summary: HelpCenter::TextNormalizer.call(summary),
      icon: settings["icon"].presence,
      cover_image_url: image_url(settings["cover_image"] || settings["image"]),
      position: position_from(settings["position"]),
      featured: boolean(settings["featured"]),
      popular: boolean(settings["popular"]),
      published_at: page.published_at,
      page_updated_at: page.updated_at,
      seo_title: seo_title,
      meta_description: meta_description
    )
    article.save!
    article
  end

  def delete_index
    HelpCategoryIndex.where(maglev_page_id: page.id).delete_all
    HelpArticleIndex.where(maglev_page_id: page.id).delete_all
    nil
  end

  def title
    published_value("title_translations").presence || page.default_title.presence || page.title
  end

  def seo_title
    published_value("seo_title_translations").presence
  end

  def meta_description
    published_value("meta_description_translations").presence
  end

  def published_value(attribute)
    payload = (page.published_payload || {}).with_indifferent_access
    (payload[attribute] || {}).with_indifferent_access[locale]
  end

  def published_sections
    @published_sections ||= begin
      sections = published_store&.sections_translations&.fetch(locale, [])
      sections.is_a?(Array) ? sections : []
    end
  end

  def published_store
    Maglev::SectionsContentStore.published.find_by(
      container_id: page.id.to_s,
      container_type: page.class.name
    )
  end

  def section_settings(type)
    section = published_sections.find { |item| item["type"] == type }
    raw_settings = section&.dig("settings") || []

    if raw_settings.is_a?(Hash)
      raw_settings.stringify_keys
    else
      raw_settings.each_with_object({}) do |setting, memo|
        next unless setting.respond_to?(:[])

        memo[setting["id"].to_s] = setting["value"]
      end
    end
  end

  def search_text(title, summary)
    content = published_sections.find { |section| section["type"] == "help_article_content" }
    values = [ title, summary ] + collect_text(content&.dig("blocks") || [])
    HelpCenter::TextNormalizer.call(values.compact.join(" "))
  end

  def collect_text(node)
    case node
    when Array
      node.flat_map { |item| collect_text(item) }
    when Hash
      if node.key?("value")
        return [] if non_text_key?(node["id"])

        return collect_text(node["value"])
      end

      node.flat_map do |key, value|
        next [] if STRUCTURAL_KEYS.include?(key.to_s) || non_text_key?(key)

        collect_text(value)
      end
    when String
      text_string?(node) ? [ node ] : []
    else
      []
    end
  end

  def text_string?(value)
    value.present? && !value.match?(URL_PATTERN) && !value.start_with?("/")
  end

  def non_text_key?(key)
    NON_TEXT_KEYS.include?(key.to_s)
  end

  def category_name_for(path)
    category = HelpCategoryIndex.find_by(locale: locale, path: path.category_path)
    return category.name if category

    path.category_path.split("/").last.tr("-", " ").capitalize
  end

  def image_url(value)
    return value if value.is_a?(String)

    value&.with_indifferent_access&.fetch(:url, nil)
  end

  def position_from(value)
    value.present? ? value.to_i : 100
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end
end

# HelpCenter::Seeder
# Creates the initial help center pages in Maglev without overwriting existing
# editorial content. Categories and articles are published unless explicitly
# marked as drafts.
#
# Example: HelpCenter::Seeder.new(site: site, data: HelpCenterSeed).call
class HelpCenter::Seeder
  def initialize(site:, data:)
    @site = site
    @data = data
  end

  def call
    Maglev::I18n.with_locale(locale) do
      ActiveRecord::Base.transaction do
        @data::CATEGORIES.each { |attributes| create_category(attributes) }
        @data::ARTICLES.each { |attributes| create_article(attributes) }
      end
    end
  end

  def publish_article(path)
    attributes = @data::ARTICLES.find { |article| article[:path] == path }
    return false if attributes.nil?

    Maglev::I18n.with_locale(locale) do
      ActiveRecord::Base.transaction do
        page = Maglev::Page.by_path(path).first
        page ||= create_page(path, attributes[:title], attributes[:summary])
        page.update!(
          sections: article_sections(attributes),
          seo_title: attributes[:title],
          meta_description: attributes[:summary]
        )
        publish(page)
      end
    end
    true
  end

  private

  attr_reader :site

  def locale
    site.default_locale_prefix
  end

  def create_category(attributes)
    return if page_exists?(attributes[:path])

    page = create_page(attributes[:path], attributes[:name], attributes[:description])
    page.update!(sections: category_sections(attributes))
    publish(page)
  end

  def create_article(attributes)
    return if page_exists?(attributes[:path])

    page = create_page(attributes[:path], attributes[:title], attributes[:summary])
    page.update!(sections: article_sections(attributes))
    publish(page) if attributes.fetch(:publish, true)
  end

  def page_exists?(path)
    Maglev::Page.by_path(path).exists?
  end

  def create_page(path, title, meta_description)
    Maglev::CreatePageService.call(
      site: site,
      attributes: {
        title: title,
        path: path,
        seo_title: title,
        meta_description: meta_description
      }
    )
  end

  def publish(page)
    Maglev::PublishService.call(site: site, page: page)
  end

  def category_sections(attributes)
    [
      section("navbar"),
      section("help_category_header",
              eyebrow: "CENTRO DE AYUDA",
              description: attributes[:description],
              icon: attributes[:icon],
              position: attributes[:position]),
      section("help_article_list",
              kicker: "GUÍAS DE LA CATEGORÍA",
              heading: "Artículos",
              description: "Elige una guía para ver el paso a paso.",
              empty_text: "Todavía no hay artículos publicados en esta categoría. Escríbenos y te ayudamos."),
      section("help_other_categories",
              kicker: "SIGUE EXPLORANDO",
              heading: "Otras categorías",
              description: "También puedes necesitar ayuda con otro tema."),
      contact_section,
      section("footer")
    ]
  end

  def article_sections(attributes)
    [
      section("navbar"),
      section("help_article_header",
              eyebrow: "CENTRO DE AYUDA",
              summary: attributes[:summary],
              icon: attributes[:icon],
              position: attributes[:position],
              featured: attributes[:featured],
              popular: attributes[:popular]),
      section("help_article_content", {}, blocks: article_blocks(attributes[:blocks])),
      section("help_article_feedback",
              question: "¿Te resultó útil este artículo?",
              yes_label: "Sí, me ayudó",
              no_label: "No del todo",
              thanks_text: "Gracias por tu valoración.",
              error_text: "No pudimos registrar tu valoración. Inténtalo de nuevo."),
      section("help_related_articles",
              kicker: "SIGUE LEYENDO",
              heading: "Artículos relacionados",
              description: "Otras guías que pueden ayudarte.",
              related_paths: Array(attributes[:related_paths]).join("\n")),
      contact_section,
      section("footer")
    ]
  end

  def contact_section
    section("institutional_content",
            kicker: "¿NO ENCUENTRAS LO QUE BUSCAS?",
            title: "Estamos para ayudarte.",
            body: "Cuéntanos qué necesitas y te responderemos lo antes posible.",
            cta: { link_type: "url", href: "/contact", text: "Contáctanos", open_new_window: false },
            variant: "lavender",
            align: "center")
  end

  def article_blocks(blocks)
    Array(blocks).map { |block| block_attributes(block) }
  end

  def block_attributes(block)
    {
      "type" => block[:type].to_s,
      "settings" => setting_pairs(block.except(:type)),
      "blocks" => []
    }
  end

  def section(type, settings = {}, blocks: [], **keyword_settings)
    {
      "type" => type,
      "settings" => setting_pairs(settings.merge(keyword_settings)),
      "blocks" => blocks
    }
  end

  def setting_pairs(settings)
    settings.map { |id, value| { "id" => id.to_s, "value" => value } }
  end
end

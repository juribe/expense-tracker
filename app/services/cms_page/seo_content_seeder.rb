# CmsPage::SeoContentSeeder
# Applies the SEO/GEO catalog to Maglev: refreshes the five help articles,
# creates or updates the commercial landing pages, and adds the internal links
# from the home page and the shared footer.
#
# Example: CmsPage::SeoContentSeeder.new(site: site, data: SeoContentSeed).call
module CmsPage
  class SeoContentSeeder
    ARTICLE_INSERT_BEFORE = %w[help_article_feedback institutional_content footer].freeze

    def initialize(site:, data: SeoContentSeed)
      @site = site
      @data = data
    end

    def call
      Maglev::I18n.with_locale(locale) do
        ActiveRecord::Base.transaction do
          data::ARTICLES.each { |attributes| refresh_article(attributes) }
          data::SUPPORTING_ARTICLES.each { |attributes| refresh_article(attributes) }
          data::LANDING_PAGES.each { |attributes| upsert_landing_page(attributes) }
          ensure_home_links
          ensure_footer_links
        end
      end
    end

    private

    attr_reader :site, :data

    def locale
      site.default_locale_prefix
    end

    def refresh_article(attributes)
      page = Maglev::Page.by_path(attributes[:path]).first
      return if page.nil?

      changes = {
        sections: replace_article_sections(page.sections, attributes),
        seo_title: attributes[:seo_title],
        meta_description: attributes[:meta_description],
        og_title: attributes[:og_title],
        og_description: attributes[:og_description],
        canonical_url: attributes[:canonical_url],
        meta_robots: "index,follow"
      }
      return if article_unchanged?(page, changes)

      page.update!(changes)
      publish(page)
    end

    def article_unchanged?(page, changes)
      page.seo_title == changes[:seo_title] &&
        page.meta_description == changes[:meta_description] &&
        page.og_title == changes[:og_title] &&
        page.og_description == changes[:og_description] &&
        page.canonical_url == changes[:canonical_url] &&
        page.meta_robots == changes[:meta_robots] &&
        same_sections?(page.sections, changes[:sections])
    end

    def replace_article_sections(sections, attributes)
      replacements = {
        "help_article_header" => article_header_section(attributes),
        "help_article_content" => article_content_section(attributes),
        "help_related_articles" => related_articles_section(attributes)
      }
      used = []

      result = Array(sections).map do |section|
        type = section["type"].to_s
        next section unless replacements.key?(type)

        used << type
        replacements[type]
      end

      missing = replacements.keys - used
      return result if missing.empty?

      position = result.index { |section| ARTICLE_INSERT_BEFORE.include?(section["type"].to_s) } || result.size
      result.insert(position, *missing.map { |type| replacements[type] })
    end

    def article_header_section(attributes)
      section(
        "help_article_header",
        eyebrow: "CENTRO DE AYUDA",
        summary: attributes[:summary],
        icon: attributes[:icon],
        position: attributes[:position],
        featured: attributes[:featured],
        popular: attributes[:popular]
      )
    end

    def article_content_section(attributes)
      section(
        "help_article_content",
        {},
        blocks: Array(attributes[:blocks]).map do |block|
          {
            "type" => block[:type].to_s,
            "settings" => setting_pairs(block.except(:type)),
            "blocks" => []
          }
        end
      )
    end

    def related_articles_section(attributes)
      section(
        "help_related_articles",
        kicker: "SIGUE LEYENDO",
        heading: "Artículos relacionados",
        description: "Otras guías que pueden ayudarte.",
        related_paths: Array(attributes[:related_paths]).join("\n")
      )
    end

    def upsert_landing_page(attributes)
      page = Maglev::Page.by_path(attributes[:path]).first
      new_page = page.nil?
      page ||= Maglev::CreatePageService.call(
        site: site,
        attributes: {
          title: attributes[:title],
          path: attributes[:path],
          seo_title: attributes[:seo_title],
          meta_description: attributes[:meta_description]
        }
      )

      changes = {
        title: attributes[:title],
        visible: true,
        sections: landing_sections(attributes),
        seo_title: attributes[:seo_title],
        meta_description: attributes[:meta_description],
        og_title: attributes[:og_title],
        og_description: attributes[:og_description],
        canonical_url: attributes[:canonical_url],
        meta_robots: "index,follow"
      }
      return if !new_page && landing_page_unchanged?(page, changes)

      page.update!(changes)
      publish(page)
    end

    def landing_page_unchanged?(page, changes)
      page.title == changes[:title] &&
        page.visible? &&
        page.seo_title == changes[:seo_title] &&
        page.meta_description == changes[:meta_description] &&
        page.og_title == changes[:og_title] &&
        page.og_description == changes[:og_description] &&
        page.canonical_url == changes[:canonical_url] &&
        page.meta_robots == changes[:meta_robots] &&
        same_sections?(page.sections, changes[:sections])
    end

    def landing_sections(attributes)
      [
        section("navbar"),
        hero_section(attributes),
        features_section(attributes[:features]),
        content_section(attributes[:content]),
        how_it_works_section(attributes[:steps]),
        links_section(attributes[:links]),
        pricing_section,
        final_cta_section(attributes[:cta]),
        section("footer")
      ].compact
    end

    def hero_section(attributes)
      hero = attributes[:hero]
      section(
        "institutional_hero",
        eyebrow: hero[:eyebrow],
        title: attributes[:h1],
        description: hero[:description],
        note: hero[:note],
        note_icon: hero[:note_icon],
        variant: hero[:variant] || "lavender",
        show_art: hero.fetch(:show_art, true),
        art_style: hero[:art_style] || "chat",
        art_greeting: hero[:art_greeting],
        art_message: hero[:art_message],
        art_reply: hero[:art_reply],
        art_badge: hero[:art_badge]
      )
    end

    def features_section(features)
      return if features.blank?

      section(
        "features",
        kicker: features[:kicker],
        title: features[:title],
        gradient_text: features[:gradient_text],
        description: features[:description],
        blocks: Array(features[:items]).map do |item|
          block("item", item)
        end
      )
    end

    def content_section(content)
      return if content.blank?

      section(
        "landing_content",
        kicker: content[:kicker],
        title: content[:title],
        gradient_text: content[:gradient_text],
        description: content[:description],
        blocks: Array(content[:blocks]).map do |content_block|
          {
            "type" => content_block[:type].to_s,
            "settings" => setting_pairs(content_block.except(:type)),
            "blocks" => []
          }
        end
      )
    end

    def how_it_works_section(steps)
      return if steps.blank?

      section(
        "how_it_works",
        kicker: steps[:kicker],
        title: steps[:title],
        gradient_text: steps[:gradient_text],
        description: steps[:description],
        blocks: Array(steps[:items]).map { |item| block("step", item) }
      )
    end

    def links_section(links)
      return if links.blank?

      section(
        "link_cards",
        kicker: links[:kicker],
        title: links[:title],
        description: links[:description],
        blocks: Array(links[:cards]).map do |card|
          settings = card.slice(:icon, :title, :description)
          block("card", settings.merge(link: link_value(card[:href], card[:title])))
        end
      )
    end

    def pricing_section
      section(
        "pricing_cta",
        kicker: "PLANES SIMPLES Y TRANSPARENTES",
        title: "Empieza gratis. ",
        gradient_text: "Crece cuando lo necesites.",
        description: "Conoce las opciones de Yogasto y elige las herramientas que mejor acompañen tu forma de organizar el dinero.",
        panel_title: "Compara las opciones vigentes.",
        panel_text: "La página de precios reúne los planes, los valores en pesos colombianos y las condiciones de pago actuales.",
        cta: link_value("/precios", "Ver precios y planes"),
        cta_hint: "Precios y condiciones vigentes en la página de precios.",
        blocks: [
          block("point", text: "Plan Gratis para empezar"),
          block("point", text: "Pagos en pesos colombianos (COP)"),
          block("point", text: "Renovación manual: tú decides cuándo continuar")
        ]
      )
    end

    def final_cta_section(cta)
      return if cta.blank?

      section(
        "final_cta",
        kicker: cta[:kicker],
        title: cta[:title],
        description: cta[:description],
        cta: link_value(cta[:href], cta[:link_text])
      )
    end

    def ensure_home_links
      page = Maglev::Page.by_path("index").first
      return if page.nil?

      sections = Array(page.sections)
      new_section = home_links_section
      index = sections.index { |section| managed_home_links?(section) }

      if index
        return if same_sections?(sections[index], new_section)

        sections = sections.dup
        sections[index] = new_section
      else
        sections = sections.dup
        footer_index = sections.index { |section| section["type"].to_s == "footer" } || sections.size
        sections.insert(footer_index, new_section)
      end

      page.update!(sections: sections)
      publish(page)
    end

    def managed_home_links?(section)
      return false unless section["type"].to_s == "link_cards"

      hrefs = Array(section["blocks"]).map { |block| link_href(block) }
      (hrefs & data::HOME_LINKS[:cards].map { |card| card[:href] }).any?
    end

    def home_links_section
      links_section(data::HOME_LINKS)
    end

    def ensure_footer_links
      data::FOOTER_LINKS.each do |link|
        FooterLink.new(
          site: site,
          label: link[:label],
          href: link[:href],
          column_title: "Yogasto"
        ).call
      end
    end

    def publish(page)
      Maglev::PublishService.call(site: site, page: page)
    end

    def section(type, settings = {}, blocks: [], **keyword_settings)
      {
        "type" => type,
        "settings" => setting_pairs(settings.merge(keyword_settings)),
        "blocks" => blocks
      }
    end

    def block(type, settings)
      {
        "type" => type,
        "settings" => setting_pairs(settings),
        "blocks" => []
      }
    end

    def setting_pairs(settings)
      settings.map { |id, value| { "id" => id.to_s, "value" => value } }
    end

    # Compares persisted JSON (string keys) with the freshly built catalog
    # (symbol keys in nested link values) without caring about key order.
    def same_sections?(current, desired)
      JSON.parse(JSON.generate(current)) == JSON.parse(JSON.generate(desired))
    end

    def link_value(href, text)
      { link_type: "url", href: href, text: text, open_new_window: false }
    end

    def link_href(block)
      Array(block["settings"]).find { |setting| setting["id"] == "link" }
                              &.fetch("value", nil)
                              &.with_indifferent_access
                              &.fetch(:href, nil)
    end
  end
end

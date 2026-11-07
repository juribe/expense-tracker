# frozen_string_literal: true

# Test helpers for the Maglev-backed help center. Pages are created as real
# Maglev pages so the indexing and publishing hooks are exercised.
module HelpCenterTestSupport
  def create_help_page!(path:, title:, sections: [], seo_title: nil, meta_description: nil)
    page = add_maglev_page(title: title, path: path)
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      page.update!(
        sections: sections,
        seo_title: seo_title || title,
        meta_description: meta_description
      )
    end
    page.reload
  end

  def publish_help_page!(page)
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      Maglev::PublishService.call(site: Maglev::Site.first, page: page)
    end
    page.reload
  end

  def help_section(type, settings = {}, blocks: [], **keyword_settings)
    {
      "type" => type,
      "settings" => help_settings(settings.merge(keyword_settings)),
      "blocks" => blocks
    }
  end

  def help_block(type, settings = {}, blocks: [], **keyword_settings)
    {
      "type" => type,
      "settings" => help_settings(settings.merge(keyword_settings)),
      "blocks" => blocks
    }
  end

  def create_help_category_index!(path: "ayuda/primeros-pasos", name: "Primeros pasos",
                                  description: "Aprende lo básico", position: 1)
    page = create_help_page!(
      path: path,
      title: name,
      sections: [ help_section("help_category_header", description: description, position: position) ]
    )

    HelpCategoryIndex.create!(
      maglev_page_id: page.id,
      locale: HelpCenter::LOCALE,
      path: path,
      name: name,
      description: description,
      position: position,
      published_at: Time.current,
      page_updated_at: Time.current
    )
  end

  def create_help_article_index!(path: "ayuda/primeros-pasos/crear-cuenta",
                                 title: "Cómo crear mi cuenta",
                                 summary: "Crea tu cuenta en Yogasto",
                                 category_path: "ayuda/primeros-pasos",
                                 category_name: "Primeros pasos",
                                 body: "Puedes crear tu cuenta desde el botón Crear cuenta.",
                                 position: 1, featured: false, popular: false)
    page = create_help_page!(path: path, title: title)

    HelpArticleIndex.create!(
      maglev_page_id: page.id,
      locale: HelpCenter::LOCALE,
      path: path,
      category_path: category_path,
      category_name: category_name,
      title: title,
      summary: summary,
      search_text: HelpCenter::TextNormalizer.call([ title, summary, body ].join(" ")),
      normalized_title: HelpCenter::TextNormalizer.call(title),
      normalized_summary: HelpCenter::TextNormalizer.call(summary),
      position: position,
      featured: featured,
      popular: popular,
      published_at: Time.current,
      page_updated_at: Time.current
    )
  end

  def create_published_category_page!(path: "ayuda/primeros-pasos", name: "Primeros pasos",
                                      description: "Aprende lo básico", position: 1)
    page = create_help_page!(
      path: path,
      title: name,
      seo_title: name,
      meta_description: description,
      sections: [
        help_section("navbar"),
        help_section("help_category_header", eyebrow: "CENTRO DE AYUDA",
                     description: description, icon: "◇", position: position),
        help_section("help_article_list", kicker: "GUÍAS DE LA CATEGORÍA", heading: "Artículos",
                     description: "Elige una guía para ver el paso a paso.",
                     empty_text: "Todavía no hay artículos publicados en esta categoría."),
        help_section("help_other_categories", kicker: "SIGUE EXPLORANDO", heading: "Otras categorías",
                     description: "También puedes necesitar ayuda con otro tema."),
        help_section("institutional_content", kicker: "¿NO ENCUENTRAS LO QUE BUSCAS?",
                     title: "Estamos para ayudarte.",
                     body: "Escríbenos y te ayudamos.",
                     cta: { link_type: "url", href: "/contact", text: "Contáctanos", open_new_window: false },
                     variant: "lavender", align: "center"),
        help_section("footer")
      ]
    )
    publish_help_page!(page)
    page
  end

  def create_published_article_page!(path: "ayuda/primeros-pasos/crear-cuenta",
                                     title: "Cómo crear mi cuenta",
                                     summary: "Crea tu cuenta en Yogasto",
                                     body: "Puedes crear tu cuenta desde el botón <strong>Crear cuenta</strong>.",
                                     related_paths: "")
    page = create_help_page!(
      path: path,
      title: title,
      seo_title: title,
      meta_description: summary,
      sections: [
        help_section("navbar"),
        help_section("help_article_header", eyebrow: "CENTRO DE AYUDA", summary: summary, icon: "▤",
                     position: 1, featured: false, popular: true),
        help_section("help_article_content", {}, blocks: [
          help_block("heading", level: "2", text: "Paso a paso"),
          help_block("paragraph", text: body),
          help_block("callout", variant: "tip", title: "Consejo", text: "Guarda tus datos antes de continuar.")
        ]),
        help_section("help_article_feedback", question: "¿Te resultó útil este artículo?",
                     yes_label: "Sí, me ayudó", no_label: "No del todo",
                     thanks_text: "Gracias por tu valoración.",
                     error_text: "No pudimos registrar tu valoración."),
        help_section("help_related_articles", kicker: "SIGUE LEYENDO", heading: "Artículos relacionados",
                     description: "Otras guías que pueden ayudarte.", related_paths: related_paths),
        help_section("institutional_content", kicker: "¿NECESITAS MÁS AYUDA?",
                     title: "Estamos para ayudarte.",
                     body: "Escríbenos y te respondemos.",
                     cta: { link_type: "url", href: "/contact", text: "Contáctanos", open_new_window: false },
                     variant: "lavender", align: "center"),
        help_section("footer")
      ]
    )
    publish_help_page!(page)
    page
  end

  private

  def help_settings(settings)
    settings.map { |id, value| { "id" => id.to_s, "value" => value } }
  end
end

# frozen_string_literal: true

require "test_helper"

class HelpCenterIndexerTest < ActiveSupport::TestCase
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
  end

  test "usa meta_description como resumen si falta la cabecera del artículo" do
    page = create_help_page!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear mi cuenta",
      sections: []
    )
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      page.meta_description = "Descripción editorial del artículo"
      page.save!
    end
    publish_help_page!(page)

    article = HelpArticleIndex.find_by(maglev_page_id: page.id)
    assert_equal "Descripción editorial del artículo", article.summary
  end

  test "no incluye URLs de imágenes en el texto de búsqueda" do
    page = create_help_page!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear mi cuenta",
      sections: [
        help_section("help_article_header", summary: "Crea tu cuenta"),
        help_section("help_article_content", {}, blocks: [
          help_block("paragraph", text: "Puedes crear tu cuenta", image: "https://cdn.example.com/foto.png")
        ])
      ]
    )
    publish_help_page!(page)

    article = HelpArticleIndex.find_by(maglev_page_id: page.id)
    assert_includes article.search_text, "puedes crear tu cuenta"
    refute_includes article.search_text, "cdn.example"
  end

  test "no incluye valores de configuración en el texto de búsqueda" do
    page = create_help_page!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Crear cuenta",
      sections: [
        help_section("help_article_header", summary: "Crea tu cuenta"),
        help_section("help_article_content", {}, blocks: [
          help_block("heading", level: "2", text: "Paso a paso"),
          help_block("paragraph", text: "Contenido del artículo")
        ])
      ]
    )
    publish_help_page!(page)

    article = HelpArticleIndex.find_by(maglev_page_id: page.id)
    assert_includes article.search_text, "paso a paso"
    refute_match(/\b2\b/, article.search_text)
  end
end

# frozen_string_literal: true

require "test_helper"

# The help center projection is derived from Maglev pages. Publishing,
# unpublishing and renaming pages must keep the projection in sync without a
# separate content admin.
class HelpCenterIndexingTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
  end

  test "publicar una categoría crea su índice" do
    page = create_help_page!(
      path: "ayuda/primeros-pasos",
      title: "Primeros pasos",
      sections: [ help_section("help_category_header", description: "Aprende lo básico", position: 2) ]
    )
    publish_help_page!(page)

    category = HelpCategoryIndex.find_by(maglev_page_id: page.id)
    assert_not_nil category
    assert_equal "ayuda/primeros-pasos", category.path
    assert_equal "Primeros pasos", category.name
    assert_equal "Aprende lo básico", category.description
    assert_equal 2, category.position
  end

  test "publicar un artículo crea su índice y lo asocia a la categoría" do
    create_published_category!
    page = create_help_page!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear mi cuenta",
      sections: [
        help_section("help_article_header", summary: "Crea tu cuenta", position: 1),
        help_section("help_article_content", {}, blocks: [
          help_block("paragraph", text: "Puedes crear tu cuenta desde el botón Crear cuenta.")
        ])
      ]
    )
    publish_help_page!(page)

    article = HelpArticleIndex.find_by(maglev_page_id: page.id)
    assert_not_nil article
    assert_equal "ayuda/primeros-pasos", article.category_path
    assert_equal "Primeros pasos", article.category_name
    assert_equal "Crea tu cuenta", article.summary
  end

  test "un artículo no publicado no se indexa" do
    create_published_category!
    create_help_page!(path: "ayuda/primeros-pasos/borrador", title: "Borrador")

    assert_nil HelpArticleIndex.find_by(path: "ayuda/primeros-pasos/borrador")
  end

  test "despublicar una página elimina su índice" do
    category = create_published_category!
    page = create_published_article!(category_path: "ayuda/primeros-pasos")

    assert_not_nil HelpArticleIndex.find_by(maglev_page_id: page.id)

    Maglev::I18n.with_locale(HelpCenter::LOCALE) { page.update!(visible: false) }

    assert_nil HelpArticleIndex.find_by(maglev_page_id: page.id)
  end

  test "cambiar el nombre de una categoría actualiza sus artículos" do
    category = create_published_category!(name: "Primeros pasos")
    page = create_published_article!(category_path: "ayuda/primeros-pasos")
    assert_equal "Primeros pasos", HelpArticleIndex.find_by(maglev_page_id: page.id).category_name

    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      category.title = "Empezando"
      category.save!
    end
    publish_help_page!(category)

    assert_equal "Empezando", HelpArticleIndex.find_by(maglev_page_id: page.id).category_name
  end

  test "el texto de las secciones se indexa para búsqueda" do
    create_published_category!
    page = create_published_article!(
      category_path: "ayuda/primeros-pasos",
      body: "Puedes registrar un gasto desde el botón Nuevo gasto."
    )

    article = HelpArticleIndex.find_by(maglev_page_id: page.id)
    assert_includes article.search_text, "registrar un gasto"
  end

  test "los paths inválidos bajo /ayuda no se indexan" do
    page = create_help_page!(
      path: "ayuda/primeros-pasos/articulo/extra",
      title: "Ruta inválida",
      sections: [ help_section("help_article_header", summary: "No debe indexarse") ]
    )
    publish_help_page!(page)

    assert_nil HelpArticleIndex.find_by(maglev_page_id: page.id)
    assert_nil HelpCategoryIndex.find_by(maglev_page_id: page.id)
  end

  test "reindexar es idempotente" do
    create_published_category!
    page = create_published_article!(category_path: "ayuda/primeros-pasos")

    assert_no_difference -> { HelpArticleIndex.count } do
      2.times { HelpCenter::Indexer.new(page).call }
    end
  end

  test "el indexador se ejecuta al publicar mediante Maglev" do
    category = create_help_page!(
      path: "ayuda/gastos",
      title: "Gastos",
      sections: [ help_section("help_category_header", description: "Gastos", position: 1) ]
    )

    publish_help_page!(category)

    assert_not_nil HelpCategoryIndex.find_by(maglev_page_id: category.id)
  end

  private

  def create_published_category!(path: "ayuda/primeros-pasos", name: "Primeros pasos")
    page = create_help_page!(
      path: path,
      title: name,
      sections: [ help_section("help_category_header", description: "Aprende lo básico", position: 1) ]
    )
    publish_help_page!(page)
    page
  end

  def create_published_article!(category_path:, body: "Contenido de ayuda")
    page = create_help_page!(
      path: "#{category_path}/crear-cuenta",
      title: "Cómo crear mi cuenta",
      sections: [
        help_section("help_article_header", summary: "Crea tu cuenta", position: 1),
        help_section("help_article_content", {}, blocks: [
          help_block("paragraph", text: body)
        ])
      ]
    )
    publish_help_page!(page)
    page
  end
end

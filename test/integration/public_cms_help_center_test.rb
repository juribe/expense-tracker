# frozen_string_literal: true

require "test_helper"

# End-to-end rendering of the Maglev-backed help center: landing, category and
# article pages, server-rendered search and SEO.
class PublicCmsHelpCenterTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
    @category = create_published_category_page!
    @expenses_category = create_published_category_page!(
      path: "ayuda/gastos",
      name: "Gastos e ingresos",
      description: "Registra y entiende tus movimientos.",
      position: 2
    )
    @article = create_published_article_page!
    @related = create_published_article_page!(
      path: "ayuda/primeros-pasos/registrar-gasto",
      title: "Cómo registrar un gasto",
      summary: "Registra tu primer movimiento",
      body: "Abre <strong>Nuevo gasto</strong> y completa los datos."
    )
  end

  test "la landing muestra buscador, categorías dinámicas y populares" do
    get "https://yogasto.co/ayuda"

    assert_response :success
    assert_match "<title>Centro de ayuda | Yogasto</title>", response.body
    assert_select "h1", count: 1
    assert_select "section.help-hero", 1
    assert_select "form[role='search'][action='/ayuda']", 1
    assert_select "input[type='search'][name='q']", 1
    assert_select "section.help-categories", 1
    assert_select "a.help-category-card[href='/ayuda/primeros-pasos']", 1
    assert_select "a.help-category-card[href='/ayuda/gastos']", 1
    assert_select "section.help-popular", 1
    assert_match "Cómo crear mi cuenta", response.body
    assert_select "a[href='/contact']", minimum: 1
  end

  test "la búsqueda del servidor muestra resultados en la landing" do
    get "https://yogasto.co/ayuda", params: { q: "cuenta" }

    assert_response :success
    assert_select "[data-help-search-results]", 1
    assert_match "Cómo crear mi cuenta", response.body
    assert_select "a[href='/ayuda/primeros-pasos/crear-cuenta']", minimum: 1
  end

  test "la página de categoría muestra su cabecera y sus artículos" do
    get "https://yogasto.co/ayuda/primeros-pasos"

    assert_response :success
    assert_match "<title>Primeros pasos | Yogasto</title>", response.body
    assert_select "h1", count: 1, text: "Primeros pasos"
    assert_select "section.help-category-hero", 1
    assert_select "section.help-article-list", 1
    assert_select "a.help-article-card[href='/ayuda/primeros-pasos/crear-cuenta']", 1
    assert_select "a.help-article-card[href='/ayuda/primeros-pasos/registrar-gasto']", 1
    assert_select "a[href='/ayuda/gastos']", minimum: 1
    assert_select "footer.site-footer", 1
    assert_match "BreadcrumbList", response.body
  end

  test "la categoría pagina los artículos cuando hay más de ocho" do
    7.times do |index|
      create_help_article_index!(
        path: "ayuda/primeros-pasos/extra-#{index}",
        title: "Artículo extra #{index}",
        summary: "Resumen extra",
        category_path: "ayuda/primeros-pasos",
        category_name: "Primeros pasos",
        position: 10 + index
      )
    end

    get "https://yogasto.co/ayuda/primeros-pasos"

    assert_response :success
    assert_select "a.help-article-card", count: 8
    assert_select ".help-pagination a[href*='page=2']", minimum: 1
  end

  test "el artículo muestra contenido enriquecido, valoración y relacionados" do
    get "https://yogasto.co/ayuda/primeros-pasos/crear-cuenta"

    assert_response :success
    assert_match "<title>Cómo crear mi cuenta | Yogasto</title>", response.body
    assert_select "h1", count: 1, text: "Cómo crear mi cuenta"
    assert_match "Paso a paso", response.body
    assert_match "Puedes crear tu cuenta", response.body
    assert_match "Consejo", response.body
    assert_select "section.help-feedback", 1
    assert_select "form[action='/ayuda/valoracion']", 1
    assert_select "input[name='page_id']", 1
    assert_select "button[data-help-rating-value='true']", 1
    assert_select "button[data-help-rating-value='false']", 1
    assert_select "a.help-article-card[href='/ayuda/primeros-pasos/registrar-gasto']", 1
    assert_match "Organization", response.body
    assert_match "TechArticle", response.body
    assert_match "article:modified_time", response.body
  end

  test "el HTML editorial se sanea antes de renderizarse" do
    create_published_article_page!(
      path: "ayuda/primeros-pasos/seguridad",
      title: "Seguridad del contenido",
      summary: "Prueba de saneamiento",
      body: "<script>alert('xss')</script><p>Texto seguro</p><img src=x onerror=\"alert(1)\"><a href='javascript:alert(1)'>Enlace</a>"
    )

    get "https://yogasto.co/ayuda/primeros-pasos/seguridad"

    assert_response :success
    assert_match "Texto seguro", response.body
    refute_includes response.body, "<script>alert('xss')</script>"
    refute_includes response.body, "onerror"
    refute_includes response.body, "javascript:"
  end

  test "la valoración sin JavaScript redirige y muestra el agradecimiento" do
    post "https://yogasto.co/ayuda/valoracion",
         params: { page_id: @article.id, helpful: "true" }

    assert_redirected_to "/ayuda/primeros-pasos/crear-cuenta"
    follow_redirect!
    assert_select ".help-flash--notice", text: "Gracias por tu valoración."
  end

  test "un artículo no publicado responde 404" do
    create_help_page!(
      path: "ayuda/primeros-pasos/borrador",
      title: "Borrador",
      sections: [ help_section("help_article_header", summary: "Borrador") ]
    )

    get "https://yogasto.co/ayuda/primeros-pasos/borrador"

    assert_response :not_found
  end

  test "el sitemap incluye las páginas publicadas del Centro de ayuda" do
    get "https://yogasto.co/sitemap.xml"

    assert_response :success
    assert_match "<loc>https://yogasto.co/ayuda</loc>", response.body
    assert_match "<loc>https://yogasto.co/ayuda/primeros-pasos</loc>", response.body
    assert_match "<loc>https://yogasto.co/ayuda/primeros-pasos/crear-cuenta</loc>", response.body
  end

  test "/contactanos redirige a la página de contacto existente" do
    get "https://yogasto.co/contactanos"

    assert_response :moved_permanently
    assert_redirected_to "/contact"
  end
end

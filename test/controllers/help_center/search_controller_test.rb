# frozen_string_literal: true

require "test_helper"

# Public JSON search used by the help center search box. It must never require
# authentication or expose unpublished articles.
class HelpCenterSearchControllerTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
    create_help_category_index!
    @article = create_help_article_index!
  end

  test "la búsqueda devuelve artículos publicados en JSON" do
    get "/ayuda/buscar", params: { q: "cuenta" }, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "cuenta", data["query"]
    assert_equal 1, data["total"]
    assert_equal "Cómo crear mi cuenta", data.dig("results", 0, "title")
  end

  test "el contrato JSON incluye título, categoría, resumen y URL amigable" do
    get "/ayuda/buscar", params: { q: "crear" }, as: :json

    result = JSON.parse(response.body).dig("results", 0)
    assert_equal "Cómo crear mi cuenta", result["title"]
    assert_equal "Primeros pasos", result["category"]
    assert_equal "Crea tu cuenta en Yogasto", result["summary"]
    assert_equal "/ayuda/primeros-pasos/crear-cuenta", result["url"]
  end

  test "una búsqueda vacía no devuelve el catálogo completo" do
    get "/ayuda/buscar", params: { q: "" }, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 0, data["total"]
    assert_empty data["results"]
  end

  test "una búsqueda sin coincidencias responde 200 con un mensaje" do
    get "/ayuda/buscar", params: { q: "hipoteca" }, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 0, data["total"]
    assert_empty data["results"]
    assert data["message"].present?
  end

  test "la búsqueda es pública para visitantes no autenticados" do
    get "/ayuda/buscar", params: { q: "cuenta" }, as: :json

    assert_response :success
  end

  test "un borrador no aparece en la búsqueda" do
    create_help_page!(path: "ayuda/primeros-pasos/borrador", title: "Borrador confidencial")

    get "/ayuda/buscar", params: { q: "borrador" }, as: :json

    assert_response :success
    assert_equal 0, JSON.parse(response.body)["total"]
  end

  test "el fallback HTML redirige a /ayuda con el término" do
    get "/ayuda/buscar", params: { q: "cuenta" }

    assert_redirected_to "/ayuda?q=cuenta"
  end
end

# frozen_string_literal: true

require "test_helper"

class HelpCenterSearchTest < ActiveSupport::TestCase
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
    create_help_category_index!
  end

  test "encuentra por título, resumen y cuerpo" do
    create_help_article_index!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear mi cuenta",
      summary: "Registro inicial",
      body: "Completa el formulario"
    )
    create_help_article_index!(
      path: "ayuda/primeros-pasos/registrar-gasto",
      title: "Registrar un gasto",
      summary: "Aprende a registrar gastos",
      body: "Desde el botón Nuevo gasto"
    )

    assert_equal [ "Cómo crear mi cuenta" ], search("registro").map(&:title)
    assert_equal [ "Registrar un gasto" ], search("nuevo gasto").map(&:title)
  end

  test "prioriza las coincidencias de título" do
    create_help_article_index!(
      path: "ayuda/primeros-pasos/registrar-gasto",
      title: "Registrar un gasto",
      summary: "Otra cosa",
      body: "Contenido"
    )
    create_help_article_index!(
      path: "ayuda/primeros-pasos/otro-articulo",
      title: "Otro artículo",
      summary: "Registrar un gasto",
      body: "Contenido"
    )

    assert_equal "Registrar un gasto", search("registrar gasto").first.title
  end

  test "exige todos los términos de la búsqueda" do
    create_help_article_index!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Crear mi cuenta",
      summary: "Registro",
      body: "Contenido"
    )
    create_help_article_index!(
      path: "ayuda/primeros-pasos/crear-presupuesto",
      title: "Crear un presupuesto",
      summary: "Planificación",
      body: "Contenido"
    )

    assert_equal [ "Crear mi cuenta" ], search("crear cuenta").map(&:title)
  end

  test "ignora mayúsculas y tildes" do
    create_help_article_index!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear mi cuenta",
      summary: "Registro",
      body: "Contenido"
    )

    assert_equal [ "Cómo crear mi cuenta" ], search("CUENTA").map(&:title)
  end

  test "no devuelve artículos de categorías no publicadas" do
    create_help_article_index!(
      path: "ayuda/oculta/articulo",
      title: "Artículo oculto",
      summary: "No debería aparecer",
      category_path: "ayuda/oculta",
      category_name: "Oculta"
    )

    assert_empty search("oculto")
  end

  test "limita el número de resultados" do
    create_help_article_index!(
      path: "ayuda/primeros-pasos/uno",
      title: "Cuenta uno",
      summary: "Resumen",
      body: "Contenido"
    )
    create_help_article_index!(
      path: "ayuda/primeros-pasos/dos",
      title: "Cuenta dos",
      summary: "Resumen",
      body: "Contenido"
    )

    assert_equal 1, HelpCenter::Search.new(query: "cuenta", limit: 1).call.size
  end

  test "escapa comodines SQL" do
    create_help_article_index!(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear mi cuenta",
      summary: "Registro",
      body: "Contenido"
    )

    assert_empty search("%")
  end

  private

  def search(query)
    HelpCenter::Search.new(query: query).call.to_a
  end
end

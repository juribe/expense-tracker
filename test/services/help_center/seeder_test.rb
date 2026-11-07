# frozen_string_literal: true

require "test_helper"

module HelpCenterSeederTestData
  CATEGORIES = [
    {
      path: "ayuda/primeros-pasos",
      name: "Primeros pasos",
      description: "Aprende lo básico",
      icon: "①",
      position: 1
    }
  ].freeze

  ARTICLES = [
    {
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Crear mi cuenta",
      summary: "Crea tu cuenta",
      icon: "✎",
      position: 1,
      popular: true,
      featured: false,
      related_paths: [],
      publish: true,
      blocks: [ { type: "paragraph", text: "<p>Contenido del artículo</p>" } ]
    },
    {
      path: "ayuda/primeros-pasos/borrador",
      title: "Borrador",
      summary: "Todavía no publicar",
      icon: "▤",
      position: 2,
      popular: false,
      featured: false,
      related_paths: [],
      publish: false,
      blocks: [ { type: "paragraph", text: "<p>Borrador</p>" } ]
    }
  ].freeze
end

class HelpCenterSeederTest < ActiveSupport::TestCase
  include PublicCmsTestSupport

  setup do
    @site = create_maglev_site!
  end

  test "crea categorías y artículos publicados como páginas Maglev" do
    HelpCenter::Seeder.new(site: @site, data: HelpCenterSeederTestData).call

    category = HelpCategoryIndex.find_by(path: "ayuda/primeros-pasos")
    article = HelpArticleIndex.find_by(path: "ayuda/primeros-pasos/crear-cuenta")

    assert_not_nil category
    assert_equal "Primeros pasos", category.name
    assert_not_nil article
    assert_equal "Crear mi cuenta", article.title
    assert article.popular?
  end

  test "el artículo marcado como borrador no se publica ni se indexa" do
    HelpCenter::Seeder.new(site: @site, data: HelpCenterSeederTestData).call

    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      page = Maglev::Page.by_path("ayuda/primeros-pasos/borrador").first
      assert_not_nil page
      refute_predicate page, :published?
    end

    assert_nil HelpArticleIndex.find_by(path: "ayuda/primeros-pasos/borrador")
  end

  test "es idempotente y no sobrescribe páginas existentes" do
    seeder = HelpCenter::Seeder.new(site: @site, data: HelpCenterSeederTestData)
    seeder.call

    assert_no_difference -> { Maglev::Page.count } do
      seeder.call
    end
  end

  test "publish_article publica y actualiza un borrador existente" do
    seeder = HelpCenter::Seeder.new(site: @site, data: HelpCenterSeederTestData)
    seeder.call

    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      refute_predicate Maglev::Page.by_path("ayuda/primeros-pasos/borrador").first, :published?
    end

    assert seeder.publish_article("ayuda/primeros-pasos/borrador")

    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      assert_predicate Maglev::Page.by_path("ayuda/primeros-pasos/borrador").first, :published?
    end
    assert_not_nil HelpArticleIndex.find_by(path: "ayuda/primeros-pasos/borrador")
  end
end

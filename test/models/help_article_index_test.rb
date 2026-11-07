# frozen_string_literal: true

require "test_helper"

class HelpArticleIndexTest < ActiveSupport::TestCase
  test "valida los campos requeridos y expone la URL" do
    article = build_article

    assert_predicate article, :valid?
    assert_equal "/ayuda/gastos/registrar-gasto", article.url
  end

  test "ordena por posición y título" do
    second = build_article(page: create_page!("ayuda/gastos/segundo"), path: "ayuda/gastos/segundo",
                           title: "Segundo", position: 2)
    first = build_article(page: create_page!("ayuda/gastos/primero"), path: "ayuda/gastos/primero",
                          title: "Primero", position: 1)
    second.save!
    first.save!

    assert_equal [ first, second ], HelpArticleIndex.ordered.to_a
  end

  test "filtra por categoría y populares" do
    popular = build_article(page: create_page!("ayuda/gastos/popular"), path: "ayuda/gastos/popular",
                            title: "Popular", popular: true)
    popular.save!
    build_article(page: create_page!("ayuda/otros/otro"), path: "ayuda/otros/otro",
                  title: "Otro", category_path: "ayuda/otros").save!

    assert_equal [ popular ], HelpArticleIndex.in_category("ayuda/gastos").popular.to_a
  end

  test "no permite dos índices para la misma página" do
    page = create_page!("ayuda/gastos/registrar-gasto")
    build_article(page: page).save!

    duplicate = build_article(page: page)

    refute_predicate duplicate, :valid?
    assert duplicate.errors[:maglev_page_id].present?
  end

  test "eliminar la página elimina su índice" do
    page = create_page!("ayuda/gastos/registrar-gasto")
    build_article(page: page).save!

    assert_difference -> { HelpArticleIndex.count }, -1 do
      page.destroy!
    end
  end

  private

  def build_article(page: nil, path: "ayuda/gastos/registrar-gasto", title: "Registrar gasto",
                    category_path: "ayuda/gastos", position: 1, popular: false)
    page ||= create_page!(path)

    HelpArticleIndex.new(
      maglev_page: page,
      locale: HelpCenter::LOCALE,
      path: path,
      category_path: category_path,
      category_name: "Gastos",
      title: title,
      summary: "Aprende a registrar un gasto",
      search_text: HelpCenter::TextNormalizer.call("#{title} Aprende a registrar un gasto"),
      normalized_title: HelpCenter::TextNormalizer.call(title),
      normalized_summary: HelpCenter::TextNormalizer.call("Aprende a registrar un gasto"),
      position: position,
      popular: popular
    )
  end

  def create_page!(path)
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      Maglev::Page.create!(title: "Página", path: path)
    end
  end
end

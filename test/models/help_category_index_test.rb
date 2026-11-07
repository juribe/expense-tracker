# frozen_string_literal: true

require "test_helper"

class HelpCategoryIndexTest < ActiveSupport::TestCase
  test "valida los campos requeridos y expone la URL" do
    category = build_category

    assert_predicate category, :valid?
    assert_equal "/ayuda/gastos", category.url
  end

  test "ordena por posición y nombre" do
    second = build_category(page: create_page!("ayuda/segunda"), path: "ayuda/segunda", name: "Segunda", position: 2)
    first = build_category(page: create_page!("ayuda/primera"), path: "ayuda/primera", name: "Primera", position: 1)
    second.save!
    first.save!

    assert_equal [ first, second ], HelpCategoryIndex.ordered.to_a
  end

  test "no permite dos índices para la misma página" do
    page = create_page!("ayuda/gastos")
    build_category(page: page).save!

    duplicate = build_category(page: page)

    refute_predicate duplicate, :valid?
    assert duplicate.errors[:maglev_page_id].present?
  end

  test "eliminar la página elimina su índice" do
    page = create_page!("ayuda/gastos")
    build_category(page: page).save!

    assert_difference -> { HelpCategoryIndex.count }, -1 do
      page.destroy!
    end
  end

  private

  def build_category(page: nil, path: "ayuda/gastos", name: "Gastos", position: 1)
    page ||= create_page!(path)

    HelpCategoryIndex.new(
      maglev_page: page,
      locale: HelpCenter::LOCALE,
      path: path,
      name: name,
      position: position
    )
  end

  def create_page!(path)
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      Maglev::Page.create!(title: "Página", path: path)
    end
  end
end

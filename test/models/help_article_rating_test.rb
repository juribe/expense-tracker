# frozen_string_literal: true

require "test_helper"

class HelpArticleRatingTest < ActiveSupport::TestCase
  test "valida el fingerprint y el valor de la valoración" do
    rating = HelpArticleRating.new(maglev_page: create_page, fingerprint: "", helpful: nil)

    refute_predicate rating, :valid?
    assert rating.errors[:fingerprint].present?
    assert rating.errors[:helpful].present?
  end

  test "no permite dos valoraciones para la misma página y fingerprint" do
    page = create_page
    HelpArticleRating.record!(maglev_page_id: page.id, fingerprint: "anon:abc", helpful: true)

    duplicate = HelpArticleRating.new(maglev_page: page, fingerprint: "anon:abc", helpful: false)

    refute_predicate duplicate, :valid?
    assert duplicate.errors[:fingerprint].present?
  end

  test "record! es idempotente y conserva el primer valor" do
    page = create_page

    assert_difference -> { HelpArticleRating.count }, 1 do
      HelpArticleRating.record!(maglev_page_id: page.id, fingerprint: "anon:abc", helpful: true)
      HelpArticleRating.record!(maglev_page_id: page.id, fingerprint: "anon:abc", helpful: false)
    end

    assert_equal true, HelpArticleRating.find_by(maglev_page_id: page.id, fingerprint: "anon:abc").helpful
  end

  test "eliminar la página elimina sus valoraciones" do
    page = create_page
    HelpArticleRating.record!(maglev_page_id: page.id, fingerprint: "anon:abc", helpful: true)

    assert_difference -> { HelpArticleRating.count }, -1 do
      page.destroy!
    end
  end

  private

  def create_page
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      Maglev::Page.create!(title: "Artículo", path: "ayuda/gastos/registrar-gasto")
    end
  end
end

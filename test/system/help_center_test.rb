# frozen_string_literal: true

require "application_system_test_case"

# Browser behavior for the help center: live search, article rating and the
# mobile layout.
class HelpCenterTest < ApplicationSystemTestCase
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
    create_published_category_page!
    create_published_article_page!
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # The driver may have restarted before mounting the page.
  end

  test "el buscador filtra en vivo y se puede limpiar" do
    visit "/ayuda"

    fill_in "help-search-input", with: "cuenta"

    assert_selector "[data-help-search-results] .help-result", text: "Cómo crear mi cuenta"
    assert_selector "[data-help-search-clear]:not([hidden])"

    find("[data-help-search-clear]").click

    assert_selector "[data-help-search-results-section][hidden]", visible: :all
    assert_equal "", find("#help-search-input").value
  end

  test "una valoración muestra el agradecimiento y desactiva los botones" do
    visit "/ayuda/primeros-pasos/crear-cuenta"

    find("[data-help-rating-value='true']").click

    assert_selector "[data-help-rating-status]", text: "Gracias por tu valoración."
    assert_selector "[data-help-rating-value='true'][disabled]"
    assert_selector "[data-help-rating-value='false'][disabled]"
  end

  test "la landing no desborda horizontalmente en móvil" do
    page.current_window.resize_to(390, 844)
    visit "/ayuda"

    columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.help-category-grid')).gridTemplateColumns.split(' ').length"
    )
    assert_equal 1, columns

    scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
    client_width = page.evaluate_script("document.documentElement.clientWidth")
    assert_operator scroll_width, :<=, client_width + 1

    font_size = page.evaluate_script(
      "parseFloat(getComputedStyle(document.querySelector('#help-search-input')).fontSize)"
    )
    assert_operator font_size, :>=, 16
  end
end

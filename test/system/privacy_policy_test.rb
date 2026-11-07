# frozen_string_literal: true

require "application_system_test_case"

# Desktop and mobile behavior of the Maglev privacy policy page.
class PrivacyPolicyTest < ApplicationSystemTestCase
  include PublicCmsTestSupport
  include PrivacyPolicyTestSupport

  setup do
    @site = create_maglev_site!
    LegalDocument::Seeder.new(site: @site, data: privacy_seed_data).call(force: true, publish: true)
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # The driver may have restarted before mounting the page.
  end

  test "el índice cambia de sección activa al navegar" do
    visit "/privacidad"

    assert_selector "[data-privacy-toc-link='responsable'].is-active"

    page.execute_script("document.querySelector('#ia').scrollIntoView({ block: 'start' })")

    assert_selector "[data-privacy-toc-link='ia'].is-active"
  end

  test "la tarjeta de ayuda no se superpone con el índice" do
    [ 1400, 900, 800, 650 ].each do |width|
      page.current_window.resize_to(width, 500)
      visit "/privacidad"

      next unless page.has_selector?(".privacy-help", visible: true)

      toc_bottom = page.evaluate_script(
        "document.querySelector('.privacy-toc').getBoundingClientRect().bottom"
      )
      toc_scroll_height = page.evaluate_script(
        "document.querySelector('.privacy-toc').scrollHeight"
      )
      toc_client_height = page.evaluate_script(
        "document.querySelector('.privacy-toc').clientHeight"
      )
      last_link_bottom = page.evaluate_script(
        "document.querySelector('.privacy-toc a:last-child').getBoundingClientRect().bottom"
      )
      help_top = page.evaluate_script(
        "document.querySelector('.privacy-help').getBoundingClientRect().top"
      )

      assert_operator toc_scroll_height, :<=, toc_client_height + 1,
                      "el índice desborda su contenedor a #{width}px"
      assert_operator help_top, :>=, toc_bottom - 1,
                      "la tarjeta de ayuda se superpone al contenedor del índice a #{width}px"
      assert_operator help_top, :>=, last_link_bottom - 1,
                      "la tarjeta de ayuda se superpone al último enlace a #{width}px"
    end
  end

  test "la página no desborda horizontalmente en móvil y el índice se compacta" do
    page.current_window.resize_to(390, 844)
    visit "/privacidad"

    display = page.evaluate_script("getComputedStyle(document.querySelector('.privacy-layout')).display")
    assert_equal "block", display

    columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.privacy-toc')).gridTemplateColumns.split(' ').length"
    )
    assert_equal 2, columns

    scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
    client_width = page.evaluate_script("document.documentElement.clientWidth")
    assert_operator scroll_width, :<=, client_width + 1

    link_height = page.evaluate_script(
      "document.querySelector('[data-privacy-toc-link=\"responsable\"]').getBoundingClientRect().height"
    )
    assert_operator link_height, :>=, 40
  end
end

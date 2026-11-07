# frozen_string_literal: true

require "application_system_test_case"

# Browser behavior of the Maglev terms and conditions page.
class TermsAndConditionsTest < ApplicationSystemTestCase
  include PublicCmsTestSupport
  include PrivacyPolicyTestSupport

  setup do
    @site = create_maglev_site!
    LegalDocument::Seeder.new(site: @site, data: terms_seed_data).call(force: true, publish: true)
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # The driver may have restarted before mounting the page.
  end

  test "el índice cambia de sección activa al navegar" do
    visit "/terminos-y-condiciones"

    assert_selector "[data-privacy-toc-link='aceptacion'].is-active"

    page.execute_script("document.querySelector('#pagos').scrollIntoView({ block: 'start' })")

    assert_selector "[data-privacy-toc-link='pagos'].is-active"
  end

  test "el índice de 14 secciones no desborda en móvil" do
    [ 375, 390 ].each do |width|
      page.current_window.resize_to(width, 844)
      visit "/terminos-y-condiciones"

      columns = page.evaluate_script(
        "getComputedStyle(document.querySelector('.privacy-toc')).gridTemplateColumns.split(' ').length"
      )
      assert_equal 2, columns

      scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
      client_width = page.evaluate_script("document.documentElement.clientWidth")
      assert_operator scroll_width, :<=, client_width + 1

      link_height = page.evaluate_script(
        "document.querySelector('[data-privacy-toc-link=\"ley\"]').getBoundingClientRect().height"
      )
      assert_operator link_height, :>=, 40
    end
  end
end

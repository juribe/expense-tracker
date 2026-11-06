# frozen_string_literal: true

require "application_system_test_case"

# El menú móvil del sitio público debe incluir los accesos de sesión, no solo
# los enlaces de secciones. En escritorio ambos accesos siguen visibles sin
# abrir el menú.
class MobileNavigationMenuTest < ApplicationSystemTestCase
  include PublicCmsTestSupport

  MOBILE_WIDTH = 500
  MOBILE_HEIGHT = 900

  setup do
    create_maglev_site!
    page.current_window.resize_to(MOBILE_WIDTH, MOBILE_HEIGHT)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # El driver puede haberse reiniciado si el test falló antes de montar la página.
  end

  test "mobile home menu includes sign in and sign up links" do
    visit root_path

    within("nav") do
      find("[data-menu-toggle]").click

      assert_selector "a[href='/users/sign_in']", visible: true
      assert_selector "a[href='/users/sign_up']", visible: true
    end
  end

  test "mobile pricing menu includes sign in and sign up links" do
    visit precios_path

    within("nav") do
      find("[data-menu-toggle]").click

      assert_selector "a[href='/users/sign_in']", visible: true
      assert_selector "a[href='/users/sign_up']", visible: true
    end
  end

  test "desktop keeps the sign in and sign up links visible" do
    page.current_window.resize_to(1400, 1000)
    visit root_path

    within("nav") do
      assert_selector "a[href='/users/sign_in']", visible: true
      assert_selector "a[href='/users/sign_up']", visible: true
    end
  end
end

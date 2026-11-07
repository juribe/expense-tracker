# frozen_string_literal: true

require "application_system_test_case"

# Browser behavior of the public Maglev security page.
class SecurityPageTest < ApplicationSystemTestCase
  include PublicCmsTestSupport

  setup do
    create_maglev_site!
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # The driver may have restarted before mounting the page.
  end

  test "el acordeón de preguntas frecuentes se abre con clic y teclado" do
    visit "/seguridad"

    first("details summary").scroll_to(:center)
    first("details summary").click
    assert_selector "details[open]", count: 1

    first("details[open] summary").click
    refute_selector "details[open]"

    second_summary = all("details summary")[1]
    second_summary.scroll_to(:center)
    second_summary.send_keys(:return)
    assert_selector "details:nth-of-type(2)[open]", count: 1
  end
  test "en escritorio el proceso y las tarjetas usan columnas" do
    page.current_window.resize_to(1400, 1000)
    visit "/seguridad"

    practice_columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.security-practice-grid')).gridTemplateColumns.split(' ').length"
    )
    process_columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.security-process-grid')).gridTemplateColumns.split(' ').length"
    )
    commitment_columns = page.evaluate_script(
      "getComputedStyle(document.querySelector('.security-grid')).gridTemplateColumns.split(' ').length"
    )
    assert_equal 3, practice_columns
    assert_equal 2, process_columns
    assert_equal 3, commitment_columns
  end

  test "las tarjetas y el proceso se apilan en móvil sin desbordarse" do
    [ 375, 390 ].each do |width|
      page.current_window.resize_to(width, 844)
      visit "/seguridad"

      scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
      client_width = page.evaluate_script("document.documentElement.clientWidth")
      assert_operator scroll_width, :<=, client_width + 1

      practice_columns = page.evaluate_script(
        "getComputedStyle(document.querySelector('.security-practice-grid')).gridTemplateColumns.split(' ').length"
      )
      process_columns = page.evaluate_script(
        "getComputedStyle(document.querySelector('.security-process-grid')).gridTemplateColumns.split(' ').length"
      )
      assert_equal 1, practice_columns
      assert_equal 1, process_columns

      summary_height = page.evaluate_script(
        "document.querySelector('#infraestructura summary').getBoundingClientRect().height"
      )
      assert_operator summary_height, :>=, 48
    end
  end
end

# frozen_string_literal: true

require "application_system_test_case"

# En móvil la lista de gastos se muestra como tarjetas apiladas. El monto y
# las acciones de cada gasto deben caber dentro del ancho del teléfono, sin
# recortes ni desplazamiento horizontal dentro de la tarjeta.
class ExpensesMobileLayoutTest < ApplicationSystemTestCase
  MOBILE_WIDTH = 500
  MOBILE_HEIGHT = 900

  setup do
    page.current_window.resize_to(MOBILE_WIDTH, MOBILE_HEIGHT)

    @user = User.create!(name: "Gastos Móvil",
                         email: "gastos-movil-#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
    @user.confirm

    category = Category.create!(user: @user, name: "Comida")
    source = MoneySource.create!(user: @user, name: "Cuenta principal", kind: "account",
                                 starting_balance: 1_000_000)
    @user.expenses.create!(category: category, money_source: source, description: "Almuerzo",
                           amount: 45_000, date: Date.current)

    sign_in @user
    visit expenses_path
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
  rescue StandardError
    # El driver puede haberse reiniciado si el test falló antes de montar la página.
  end

  test "keeps the amount and actions inside the mobile viewport" do
    layout = page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector("#tableCard");
        const row = document.querySelector(".mobile-item");
        const viewport = document.documentElement.clientWidth;
        const targets = row.querySelectorAll(".amount, .mobile-actions .btn");
        const overflowing = Array.from(targets).filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.left < 0 || rect.right > viewport + 1;
        }).length;

        return {
          overflowing,
          cardScrollsHorizontally: card.scrollWidth > card.clientWidth + 1
        };
      })()
    JS

    assert_equal 0, layout["overflowing"],
                 "el monto y las acciones deben quedar dentro del viewport móvil"
    refute layout["cardScrollsHorizontally"],
           "la tarjeta de gastos no debe requerir scroll horizontal en móvil"
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "aside.left-sidebar", wait: 10
  end
end

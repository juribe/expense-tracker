# frozen_string_literal: true

require "application_system_test_case"

# El modal de gastos mensuales reutiliza un único formulario para crear y
# editar. El selector de categoría visible debe quedar sincronizado con el
# select nativo cada vez que el formulario se reinicia, sin arrastrar la
# categoría de la plantilla editada anteriormente.
class MonthlyExpensesFormModalTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Monthly Form User", email: "monthly_form@example.com", password: "password123")
    @services = Category.create!(user: @user, name: "Servicios", category_type: "expense", is_default: false)
    @transport = Category.create!(user: @user, name: "Transporte", category_type: "expense", is_default: false)
    @first_template = create_template("Internet hogar", @services)
    @second_template = create_template("Pasajes mensuales", @transport)
  end

  test "add form starts without a stale category after editing a template" do
    sign_in @user
    visit monthly_expenses_path

    open_edit_modal(@first_template)
    assert_equal "Servicios", category_search.value
    close_form_modal

    find('[data-testid="add-recurring"]').click
    assert_selector "#recurringFormModal.show"

    assert_equal "", category_search.value
    assert_equal "", category_select.value
    assert_equal "true", blank_option["aria-selected"]
    assert_equal "false", category_option(@services)["aria-selected"]
    assert_equal "false", category_option(@transport)["aria-selected"]
  end

  test "editing a second template shows its own category" do
    sign_in @user
    visit monthly_expenses_path

    open_edit_modal(@first_template)
    assert_equal "Servicios", category_search.value
    close_form_modal

    open_edit_modal(@second_template)

    assert_equal "Transporte", category_search.value
    assert_equal @transport.id.to_s, category_select.value
    assert_equal "true", category_option(@transport)["aria-selected"]
    assert_equal "false", category_option(@services)["aria-selected"]
  end

  test "editing a template shows its amount without inflation" do
    sign_in @user
    visit monthly_expenses_path

    open_edit_modal(@first_template)

    assert_equal "120.000", find("#recurring_template_amount").value
  end

  private

  def create_template(description, category)
    @user.recurring_templates.create!(
      category: category, kind: "expense", description: description,
      amount: 120_000, frequency: "monthly", source: "manual", payment_day: 10
    )
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "Email", with: user.email, match: :first
    fill_in "Password", with: "password123", match: :first
    click_button I18n.t("auth.sign_in")
  end

  def open_edit_modal(template)
    within "tr[data-testid='recurring-row'][data-id='#{template.id}']" do
      find('[data-testid="edit"]').click
    end
    assert_selector "#recurringFormModal.show"
  end

  def close_form_modal
    find("#recurringFormModal .btn-close").click
    assert_no_selector "#recurringFormModal.show"
  end

  def category_search
    find("#recurring_template_category_id_search")
  end

  def category_select
    find("#recurring_template_category_id", visible: :all)
  end

  def blank_option
    find("#recurring_template_category_id_listbox [role='option'][data-value='']", visible: :all)
  end

  def category_option(category)
    find("#recurring_template_category_id_listbox [role='option'][data-value='#{category.id}']", visible: :all)
  end
end

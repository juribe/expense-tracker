# frozen_string_literal: true

require "test_helper"

class CategoryPickerHelperTest < ActionView::TestCase
  tests CategoryPickerHelper

  TEMPLATE = "<%= category_picker(form, :category_id, categories, **options) %>"

  setup do
    @user = User.create!(name: "Picker User", email: "picker_#{Time.now.to_i}@example.com", password: "password123")
    @comida = create_default("Comida")
    @restaurante = create_default("Restaurante", parent: @comida)
    @transporte = create_default("Transporte")
    @crypto = create_custom("Crypto")
  end

  # --- Combobox wiring ---

  test "renders a combobox text input wired to the listbox" do
    input = combobox(picker_html)

    assert_equal "expense_category_id_search", input["id"]
    assert_equal "expense_category_id_listbox", input["aria-controls"]
    assert_equal "false", input["aria-expanded"]
    assert_equal "list", input["aria-autocomplete"]
  end

  test "renders a listbox holding one option per category" do
    listbox = listbox_node(picker_html)

    assert_equal "expense_category_id_listbox", listbox["id"]
    assert_equal "listbox", listbox["role"]
    assert_equal [ @restaurante.id, @comida.id, @transporte.id, @crypto.id ].sort.map(&:to_s),
                 listbox.css("[role=option][data-value]").map { |node| node["data-value"] }.sort
  end

  test "marks the wrapper so the javascript can find and bind it" do
    wrapper = picker_html(testid: "expense-category-picker").at_css("[data-category-picker]")

    assert_not_nil wrapper
    assert_equal "expense-category-picker", wrapper["data-testid"]
  end

  test "gives the label and the visible input the same target" do
    doc = picker_html(label: "Categoría")
    label = doc.at_css("label")

    assert_equal "Categoría", label.text.strip
    assert_equal "expense_category_id_search", label["for"]
    assert_equal "form-label", label["class"]
  end

  test "omits the label when none is given" do
    assert_nil picker_html(label: nil).at_css("label")
  end

  test "names the combobox itself when no visible label is rendered" do
    input = combobox(picker_html(label: nil))

    assert_equal I18n.t("category_picker.search_placeholder"), input["aria-label"]
  end

  test "does not duplicate the label when a visible one is rendered" do
    assert_nil combobox(picker_html(label: "Categoría"))["aria-label"]
  end

  # --- Option list ---

  test "renders one alphabetical list mixing defaults and custom categories" do
    doc = picker_html

    assert_equal [ @comida.id, @crypto.id, @restaurante.id, @transporte.id ].map(&:to_s),
                 listbox_node(doc).css("[role=option][data-value]").map { |node| node["data-value"] }
  end

  test "renders a flat list with no group headers or indentation" do
    doc = picker_html

    assert_empty doc.css("[data-group-header], [data-indent]")
    assert_equal "Restaurante", doc.at_css("[role=option][data-value='#{@restaurante.id}']").text.strip
  end

  # --- The native select that keeps the form working ---

  test "keeps a native select with the original id and name so forms still submit" do
    select = picker_html.at_css("select#expense_category_id")

    assert_not_nil select
    assert_equal "expense[category_id]", select["name"]
  end

  test "keeps every category as an option on the native select" do
    select = picker_html.at_css("select#expense_category_id")

    assert_equal [ @comida.id, @restaurante.id, @transporte.id, @crypto.id ].sort.map(&:to_s),
                 select.css("option").map { |node| node["value"] }.sort
  end

  test "hides the native select from the page and from assistive tech" do
    select = picker_html.at_css("select#expense_category_id")

    assert_includes select["class"], "d-none"
    assert_equal "true", select["aria-hidden"]
  end

  test "marks the selected option on both the listbox and the native select" do
    doc = picker_html(expense: Expense.new(category_id: @comida.id))

    assert_equal "true", doc.at_css("[role=option][data-value='#{@comida.id}']")["aria-selected"]
    assert_equal "false", doc.at_css("[role=option][data-value='#{@transporte.id}']")["aria-selected"]
    assert_equal [ @comida.id.to_s ], doc.css("select#expense_category_id option[selected]").map { |node| node["value"] }
  end

  test "prefills the search input with the selected category name" do
    assert_equal "Comida", combobox(picker_html(expense: Expense.new(category_id: @comida.id)))["value"]
  end

  test "takes an explicit value for forms with no model behind them" do
    doc = picker_html(value: @transporte.id.to_s)

    assert_equal "Transporte", combobox(doc)["value"]
    assert_equal [ @transporte.id.to_s ], doc.css("select#expense_category_id option[selected]").map { |node| node["value"] }
  end

  test "renders when the form has no object to read a value from" do
    form = ActionView::Helpers::FormBuilder.new(:expense, false, _view, {})
    html = _view.render(inline: TEMPLATE, locals: { form: form, categories: Category.all, options: {} })

    assert_includes Nokogiri::HTML5.fragment(html).to_html, "role=\"combobox\""
  end

  test "renders a leading blank option that clears the value" do
    option = picker_html(include_blank: "Sin categoría").css("[role=option]").first

    assert_equal "", option["data-value"]
    assert_equal "Sin categoría", option.text.strip
  end

  test "gives every option an id so aria-activedescendant can point at it" do
    doc = picker_html(include_blank: "Sin categoría")
    ids = doc.css("[role=option]").map { |node| node["id"] }

    assert_equal ids.compact, ids
    assert_equal ids.uniq, ids
  end

  test "renders a leading prompt option that clears the value" do
    option = picker_html(prompt: "Elige una categoría").css("[role=option]").first

    assert_equal "", option["data-value"]
    assert_equal "Elige una categoría", option.text.strip
  end

  test "renders no leading option when neither blank nor prompt is given" do
    values = picker_html.css("[role=option][data-value]").map { |node| node["data-value"] }

    assert_not_includes values, ""
  end

  # --- Options that views need to pass through ---

  test "disables both the visible input and the native select" do
    doc = picker_html(disabled: true)

    assert_not_nil combobox(doc)["disabled"]
    assert_not_nil doc.at_css("select#expense_category_id")["disabled"]
  end

  test "moves required off the hidden select onto the visible input" do
    doc = picker_html(required: true)

    assert_nil doc.at_css("select#expense_category_id")["required"]
    assert_equal "true", combobox(doc)["aria-required"]
    assert_equal "true", doc.at_css("[data-category-picker]")["data-required"]
  end

  test "renders a hidden message the javascript shows when a required field is empty" do
    doc = picker_html(required: true)
    feedback = doc.at_css("[data-required-message]")

    assert_not_nil feedback
    assert_not_nil feedback["hidden"]
    assert_equal I18n.t("category_picker.required"), feedback["data-required-message"]
  end

  test "renders no required message when the field is optional" do
    assert_nil picker_html.at_css("[data-required-message]")
  end

  test "accepts an explicit id so scripts can target the field" do
    doc = picker_html(id: "import_category")

    assert_not_nil doc.at_css("select#import_category")
    assert_equal "import_category_search", combobox(doc)["id"]
  end

  test "wires aria-describedby onto the visible input" do
    doc = picker_html(aria_describedby: "parentHelp")

    assert_equal "parentHelp", combobox(doc)["aria-describedby"]
  end

  test "carries a validation error class through to the visible input" do
    input = combobox(picker_html(class: "form-select is-invalid"))

    assert_includes input["class"], "is-invalid"
  end

  test "renders a listbox message for an empty result set" do
    doc = picker_html

    assert_equal I18n.t("category_picker.no_results"), doc.at_css("[data-no-results]")["data-no-results"]
  end

  test "renders nothing but the select when there are no categories" do
    doc = picker_html(categories: [])

    assert_empty doc.css("[role=option][data-value]")
    assert_not_nil doc.at_css("select#expense_category_id")
  end

  private

  def picker_html(categories: Category.all, expense: Expense.new, **options)
    form = ActionView::Helpers::FormBuilder.new(:expense, expense, _view, {})
    html = _view.render(inline: TEMPLATE, locals: { form: form, categories: categories, options: options })
    Nokogiri::HTML5.fragment(html)
  end

  def combobox(doc)
    doc.at_css("[role=combobox]")
  end

  def listbox_node(doc)
    doc.at_css("[role=listbox]")
  end

  def create_default(name, parent: nil)
    Category.create!(name: name, is_default: true, category_type: "expense", parent: parent)
  end

  def create_custom(name)
    Category.create!(name: name, is_default: false, category_type: "expense", user: @user)
  end
end

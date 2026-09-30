# frozen_string_literal: true

# CategoryPickerField
# Everything the searchable category dropdown needs: the form field it
# replaces, the ordered options to offer, and the element ids its markup,
# stylesheet and javascript all address.
#
# Swapping a `collection_select` for this keeps the same field id and name on
# a native (hidden) select, so form submission and existing selectors keep
# working while the visible control becomes a type-ahead combobox.
#
# Example: CategoryPickerField.new(form, :category_id, categories, label: "Categoría").search_id
class CategoryPickerField
  SEARCH_SUFFIX = "_search"
  LISTBOX_SUFFIX = "_listbox"
  SEARCH_CLASS = "form-control category-picker__input"
  SELECT_CLASS = "form-select"

  attr_reader :form, :method, :categories, :label, :label_class, :blank_option,
              :placeholder, :required, :disabled, :describedby, :field_class, :testid

  def initialize(form, method, categories, **options)
    @form = form
    @method = method
    @categories = categories
    @label = options[:label]
    @label_class = options.fetch(:label_class, "form-label")
    @blank_option = build_blank_option(options)
    @placeholder = options.fetch(:placeholder, I18n.t("category_picker.search_placeholder"))
    @required = options.fetch(:required, false)
    @disabled = options.fetch(:disabled, false)
    @describedby = options[:aria_describedby]
    @field_class = options[:class].to_s
    @testid = options[:testid]
    @field_id = options[:id] || form.field_id(method)
    @value = options[:value]
  end

  def field_id
    @field_id
  end

  def search_id
    "#{field_id}#{SEARCH_SUFFIX}"
  end

  def listbox_id
    "#{field_id}#{LISTBOX_SUFFIX}"
  end

  def options
    @options ||= CategoryOptionList.new(categories).options
  end

  def empty?
    options.empty?
  end

  def search_class
    [ SEARCH_CLASS, field_class ].reject(&:blank?).join(" ")
  end

  # `required` stays off the select: a required control the browser cannot
  # focus aborts submission with an unreachable error. The combobox enforces
  # it instead, and the model still validates server-side.
  def select_html_options
    options = {
      id: field_id,
      class: "#{SELECT_CLASS} d-none",
      aria: { hidden: true },
      tabindex: -1
    }
    options[:disabled] = true if disabled
    options
  end

  def select_options
    options = {}
    options[:selected] = selected_id if selected_id.present?
    options[:include_blank] = blank_option[:label] if blank_option
    options
  end

  # The native select stays in the DOM so forms submit exactly as before.
  def select
    form.collection_select(method, categories, :id, :name, select_options, select_html_options)
  end

  def search_html_options
    options = {
      type: "text",
      id: search_id,
      name: nil,
      class: search_class,
      role: "combobox",
      value: selected_label,
      placeholder: placeholder,
      autocomplete: "off",
      spellcheck: "false",
      "aria-expanded": "false",
      "aria-haspopup": "listbox",
      "aria-autocomplete": "list",
      "aria-controls": listbox_id
    }
    # A visible <label for> already names the combobox; without one it needs
    # an explicit accessible name.
    options["aria-label"] = accessible_name if label.blank?
    options["aria-describedby"] = describedby if describedby
    options["aria-required"] = "true" if required
    options[:disabled] = true if disabled
    options
  end

  def accessible_name
    label.presence || placeholder
  end

  def selected_label
    selected_option&.label
  end

  def selected?(value)
    selected_option&.id.to_s == value.to_s
  end

  def no_results_label
    I18n.t("category_picker.no_results")
  end

  def toggle_label
    I18n.t("category_picker.toggle")
  end

  def required_message
    I18n.t("category_picker.required")
  end

  private

  def selected_option
    return @selected_option if defined?(@selected_option)

    @selected_option = options.find { |option| option.id.to_s == selected_id.to_s }
  end

  def selected_id
    return @value if defined?(@value) && !@value.nil?

    object = form.object
    return nil unless object.respond_to?(method)

    object.public_send(method)
  end

  def build_blank_option(options)
    if options.key?(:include_blank) && options[:include_blank]
      { value: "", label: options[:include_blank] == true ? "" : options[:include_blank] }
    elsif options.key?(:prompt) && options[:prompt]
      { value: "", label: options[:prompt] }
    end
  end
end

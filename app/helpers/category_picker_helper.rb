# frozen_string_literal: true

# CategoryPickerHelper
# Renders the type-ahead category dropdown used throughout the app.
#
# Methods: category_picker, category_picker_tag
#
# Example:
#   category_picker(f, :category_id, @categories, label: t("common.category"))
module CategoryPickerHelper
  def category_picker(form, method, categories, **options)
    render "shared/category_picker", field: CategoryPickerField.new(form, method, categories, **options)
  end

  # For pickers outside a form builder, such as modals that only feed values
  # into other fields with javascript.
  def category_picker_tag(categories, method: :category_id, **options)
    form = ActionView::Helpers::FormBuilder.new(nil, nil, self, {})
    category_picker(form, method, categories, **options)
  end
end

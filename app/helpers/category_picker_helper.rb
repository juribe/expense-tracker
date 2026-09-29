# frozen_string_literal: true

# CategoryPickerHelper
# Renders the type-ahead category dropdown used throughout the app.
#
# Methods: category_picker
#
# Example:
#   category_picker(f, :category_id, @categories, label: t("common.category"))
module CategoryPickerHelper
  def category_picker(form, method, categories, **options)
    render "shared/category_picker", field: CategoryPickerField.new(form, method, categories, **options)
  end
end

# frozen_string_literal: true

module ImportsHelper
  # Only category problems are fixable from the preview (with a category
  # list to choose from); invalid amount/kind values come from the file and
  # need a re-upload.
  def import_category_fixable?(row)
    row["kind_valid"] && row["amount_valid"] && @category_options[row["kind"]].present?
  end

  def import_preview_money(row)
    amount = RecurringTemplateImporter.normalize_amount(row["amount"])
    return "—" if amount.nil?

    number_to_currency(amount)
  end

  def import_kind_badge(row)
    label, style = case row["kind"]
      when "expense" then [t("imports.preview.kind_expense"), "bg-danger"]
      when "income" then [t("imports.preview.kind_income"), "bg-success"]
      else [row["kind"].presence || "—", "bg-secondary"]
    end

    content_tag(:span, label, class: "badge #{style}")
  end
end

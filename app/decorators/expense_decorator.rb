# frozen_string_literal: true

# Presentation helpers for expenses rendered in lists (index table, mobile
# list, detail drawer).
class ExpenseDecorator < ApplicationDecorator
  delegate :amount, :category, :date, :description, :money_source,
           :recurring_template_id, to: :object

  def description_or_fallback
    object.description.presence || I18n.t("expenses.no_description")
  end

  # Lowercased description for aria-labels, falling back the same way.
  def lowercase_description
    description_or_fallback.downcase
  end

  def source_name
    object.money_source&.name.to_s
  end

  def recurring_linked?
    object.recurring_template_id.present?
  end
end

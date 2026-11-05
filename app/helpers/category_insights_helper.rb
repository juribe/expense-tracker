# frozen_string_literal: true

# CategoryInsightsHelper
# Presentation helpers for the savings-opportunity list and detail.
#
# Methods: category_insight_potential_label, category_insight_potential_short_label,
# category_insight_activity_label, category_insight_cycle_amount,
# category_insight_cycle_hint
#
# Example: category_insight_potential_label(category) # => "Potencial alto"
module CategoryInsightsHelper
  POTENTIAL_LABELS = {
    "high" => "Potencial alto",
    "medium" => "Potencial medio",
    "low" => "Potencial bajo"
  }.freeze

  POTENTIAL_SHORT_LABELS = {
    "high" => "Alto",
    "medium" => "Medio",
    "low" => "Bajo"
  }.freeze

  def category_insight_potential_label(category)
    POTENTIAL_LABELS.fetch(category.savings_potential_level, POTENTIAL_LABELS["low"])
  end

  def category_insight_potential_short_label(category)
    POTENTIAL_SHORT_LABELS.fetch(category.savings_potential_level, POTENTIAL_SHORT_LABELS["low"])
  end

  def category_insight_activity_label(row)
    if row[:average].positive?
      count = row[:insight][:cycles_with_spending]
      "Promedio de #{count} #{count == 1 ? "ciclo" : "ciclos"} con actividad"
    elsif row[:current_cycle].positive?
      "Actividad registrada en el ciclo actual"
    else
      "Aún no hay historial suficiente para comparar"
    end
  end

  def category_insight_cycle_amount(row)
    return MoneyFormat.currency(row[:current_cycle]) if row[:current_cycle].positive?
    return MoneyFormat.currency(0) if row[:average].positive?

    nil
  end

  def category_insight_cycle_hint(row)
    row[:current_cycle].positive? ? "Gasto en el ciclo" : "Sin gastos este ciclo"
  end

  def category_insight_cycle_range(cycle)
    "#{cycle.label} · #{cycle.range_label}"
  end
end

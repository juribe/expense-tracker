# frozen_string_literal: true

# AlertsHelper
# Methods: alert_icon, alert_chip_text_class, alert_level_label, alert_message
#
# Example: alert_message(alert) # => "Restaurantes usó el 82% de su presupuesto mensual de $800.000."
module AlertsHelper
  KIND_ICONS = {
    "budget_threshold" => "bi-exclamation-triangle",
    "budget_exceeded" => "bi-exclamation-circle",
    "spending_increase" => "bi-graph-up-arrow"
  }.freeze

  KIND_CHIP_CLASS = {
    "budget_threshold" => "bg-warning bg-opacity-10 text-warning",
    "budget_exceeded" => "bg-danger bg-opacity-10 text-danger",
    "spending_increase" => "bg-primary bg-opacity-10 text-primary"
  }.freeze

  def alert_icon(alert)
    KIND_ICONS.fetch(alert.kind, "bi-bell")
  end

  def alert_chip_text_class(alert)
    KIND_CHIP_CLASS.fetch(alert.kind, "bg-secondary bg-opacity-10 text-secondary")
  end

  def alert_level_label(alert)
    case alert.kind
    when "budget_threshold" then t("alerts.level_near_limit", default: "Cerca del límite")
    when "budget_exceeded" then t("alerts.level_over_budget", default: "Sobre el presupuesto")
    when "spending_increase" then t("alerts.level_spending_increase", default: "Aumento de gasto")
    else ""
    end
  end

  def alert_message(alert)
    case alert.kind
    when "budget_threshold"
      t("alerts.message_threshold",
        category: alert.category.name,
        pct: alert.pct,
        budget: number_to_currency(alert.budget_amount))
    when "budget_exceeded"
      excess = alert.amount.to_d - alert.budget_amount.to_d
      t("alerts.message_exceeded",
        category: alert.category.name,
        amount: number_to_currency(excess))
    when "spending_increase"
      t("alerts.message_increase",
        category: alert.category.name,
        pct: alert.pct,
        amount: number_to_currency(alert.amount),
        previous: number_to_currency(alert.previous_amount))
    else
      ""
    end
  end
end
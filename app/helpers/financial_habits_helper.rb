# frozen_string_literal: true

module FinancialHabitsHelper
  HABIT_PRESENTATION = {
    "income_spending_pattern" => { icon: "cash", pill: "Patrón detectado", tone: "blue" },
    "spending_time_pattern" => { icon: "clock", pill: "Rutina observada", tone: "blue" },
    "spending_weekday_pattern" => { icon: "calendar", pill: "Rutina observada", tone: "blue" },
    "merchant_frequency" => { icon: "repeat", pill: "Rutina recurrente", tone: "green" },
    "credit_usage_pattern" => { icon: "credit-card", pill: "Oportunidad de revisión", tone: "amber" },
    "cycle_end_spending" => { icon: "calendar-stats", pill: "Patrón de ciclo", tone: "blue" },
    "behavior_change" => { icon: "trending-up", pill: "Cambio observado", tone: "amber" },
    "planning_opportunity" => { icon: "calendar-check", pill: "Oportunidad de planificación", tone: "green" }
  }.freeze

  def habit_presentation(discovery)
    HABIT_PRESENTATION.fetch(discovery[:key].to_s, { icon: "sparkles", pill: "Patrón detectado", tone: "blue" })
  end

  def habit_metric(discovery)
    evidence = discovery[:evidence] || {}

    case discovery[:key].to_s
    when "income_spending_pattern"
      { value: "#{evidence[:post_window_pct]}%", label: "De tus gastos ocurre en los primeros #{evidence[:post_window_days]} días", note: "Periodo posterior al ingreso" }
    when "spending_time_pattern"
      { value: "#{evidence[:peak_pct]}%", label: "De tus compras ocurre en esa franja", note: "Franja más activa: #{evidence[:peak_slot_label]}" }
    when "spending_weekday_pattern"
      { value: "#{evidence[:peak_weekday_pct]}%", label: "De tus movimientos ocurre los #{evidence[:peak_weekday]}", note: "Día más activo" }
    when "merchant_frequency"
      { value: "#{evidence[:merchants_count]} comercios", label: "Con visitas repetidas", note: "Más frecuente: #{evidence[:top_visits]} visitas" }
    when "credit_usage_pattern"
      { value: "#{evidence[:credit_pct]}%", label: "De tus gastos se pagó con crédito", note: "#{evidence[:credit_expenses_count]} transacciones" }
    when "cycle_end_spending"
      { value: "#{evidence[:last_days_pct]}%", label: "De tus gastos ocurre en los últimos #{evidence[:last_days]} días del ciclo", note: "#{evidence[:cycles_observed]} ciclos analizados" }
    when "behavior_change"
      { value: "#{evidence[:delta_pct].to_i.positive? ? '+' : ''}#{evidence[:delta_pct]}%", label: "Frente a tu promedio habitual", note: "Periodo actual vs histórico" }
    when "planning_opportunity"
      { value: "#{evidence[:patterns_count]} gastos", label: "Podrías anticipar", note: "Pagos con cierta regularidad" }
    else
      { value: "—", label: "Patrón detectado", note: discovery[:period] }
    end
  end
end
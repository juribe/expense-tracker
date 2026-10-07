module DashboardHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::DateHelper

  def currency(amount)
    number_to_currency(amount)
  end

  def category_label(name, amount)
    "#{name} (#{currency(amount)})"
  end

  def format_date(date)
    l(date, format: :short)
  end

  # The expenses card speaks in financial cycles when the user configured
  # paydays; the calendar month otherwise (the card's data already follows
  # the resolved period).
  def dashboard_expenses_title(cycle)
    cycle ? t("dashboard.expenses_this_cycle", default: "Gastos de este ciclo") : t("dashboard.expenses_this_month", default: "Gastos de este mes")
  end

  def dashboard_no_expenses_label(cycle)
    cycle ? t("dashboard.no_expenses_this_cycle", default: "No hay gastos este ciclo") : t("dashboard.no_expenses_this_month", default: "No hay gastos este mes")
  end
end
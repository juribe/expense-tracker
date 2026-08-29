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
end
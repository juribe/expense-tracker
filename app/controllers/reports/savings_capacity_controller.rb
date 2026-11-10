# frozen_string_literal: true

# Reports::SavingsCapacityController
# GET /reports/savings_capacity — read-only projection of the money that could
# remain at the end of a future financial cycle. The selector only offers
# future cycles; the two estimates and the percentage are display options.
class Reports::SavingsCapacityController < Reports::BaseController
  def index
    @report = Reports::SavingsCapacity.new(
      user: current_user,
      filter: report_filters,
      cycle: selected_cycle,
      basic_reserve_enabled: boolean_param(:basic_reserve, default: true),
      include_previous_expenses: boolean_param(:include_previous_expenses, default: true),
      basic_reserve_percentage: params[:basic_reserve_percentage]
    ).call
  end

  private

  # This report is not narrowed by category or money source: its inputs are
  # the recurring configuration and the previous cycle's consumption.
  def report_filter_params
    {}
  end

  def selected_cycle
    @selected_cycle ||= Reports::SavingsCapacity.cycle_from_param(current_user, params[:cycle])
  end

  def boolean_param(key, default:)
    return default unless params.key?(key)

    ActiveModel::Type::Boolean.new.cast(params[key])
  end
end

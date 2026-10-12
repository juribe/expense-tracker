# frozen_string_literal: true

# DebtCapacityController
# GET /debt_capacity — independent debt and borrowing-capacity overview.
class DebtCapacityController < ApplicationController
  before_action :authenticate_user!

  def show
    @debt_capacity = build_overview
  end

  def comparison
    @debt_capacity = build_overview
    render partial: "debt_capacity/comparison"
  end

  private

  def build_overview
    DebtCapacity::Overview.new(
      user: current_user,
      month: Date.current,
      target_percentage: threshold_param(:target, current_user.debt_capacity_target_percentage),
      alert_percentage: threshold_param(:alert, current_user.debt_capacity_alert_percentage),
      comparison_options: comparison_options
    ).call
  end

  def comparison_options
    { debt_id: params[:debt_id], amount: comparison_amount, mode: comparison_mode,
      installment_count: comparison_installment_count }
  end

  def comparison_amount
    return DebtCapacity::Comparison::DEFAULT_AMOUNT if params[:amount].blank?

    MoneyFormat.normalize(params[:amount].to_s).to_d
  rescue ArgumentError, TypeError
    DebtCapacity::Comparison::DEFAULT_AMOUNT
  end

  def comparison_mode
    DebtCapacity::Comparison::MODES.include?(params[:mode].to_s) ? params[:mode].to_s : "reduce_term"
  end

  def comparison_installment_count
    return if params[:installment_count].blank?

    value = params[:installment_count].to_i
    value.positive? ? value : nil
  end

  def threshold_param(name, default)
    value = params[name]
    return default if value.blank? || value.to_d <= 0 || value.to_d > 100

    value.to_d
  end
end

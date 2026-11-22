# frozen_string_literal: true

# MoneyTrackingController
# GET/PATCH /settings/money_tracking
# First-run choice of the tracking mode (simple / detailed) and the settings
# page that changes it later. The membership and its dates are never touched.
class MoneyTrackingController < ApplicationController
  before_action :authenticate_user!
  before_action :require_detailed_money_tracking, only: :update_default_source

  def show
    if current_user.money_tracking_mode_selected?
      @selected_mode = current_user.money_tracking_mode
      if current_user.money_tracking_detailed?
        @default_source_options = current_user.money_sources.active.payment_sources
                                              .includes(:credit_account).order(:kind, :name)
      end
      render :show
    else
      @selected_mode = "simple"
      render :onboarding
    end
  end

  def update_default_source
    source_id = UuidParams.normalize(params[:default_money_source_id])
    source = source_id && current_user.money_sources.active.payment_sources.find_by(id: source_id)
    if source_id.present? && source.nil?
      redirect_to money_tracking_path, alert: t("money_tracking.invalid_default_source")
      return
    end

    current_user.update!(default_money_source: source)
    redirect_to money_tracking_path, notice: t("money_tracking.default_source_updated")
  end

  def update
    mode = params[:money_tracking_mode].to_s
    unless mode.in?(User::MONEY_TRACKING_MODES)
      redirect_to money_tracking_path, alert: t("money_tracking.invalid_mode")
      return
    end

    if requires_simple_confirmation?(mode)
      @selected_mode = mode
      render :confirm
      return
    end

    was_selected = current_user.money_tracking_mode_selected?
    result = MoneySources::ModeSwitch.new(user: current_user, mode: mode).call

    if result.success?
      redirect_to(was_selected ? money_tracking_path : dashboard_path,
                  notice: t("money_tracking.updated"))
    else
      redirect_to money_tracking_path, alert: result.errors.to_sentence
    end
  end

  private

  def requires_simple_confirmation?(mode)
    mode == "simple" && current_user.money_tracking_detailed? && params[:confirmed].to_s != "1"
  end
end

# frozen_string_literal: true

# AlertSettingsController
# GET/PATCH /settings/alerts: the three per-user alert toggles.
class AlertSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @preferences = current_user.alert_prefs
  end

  def update
    @preferences = current_user.alert_prefs
    if @preferences.update(alert_preferences_params)
      redirect_to alert_settings_path, notice: t("alerts.settings_saved", default: "Preferencias guardadas")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def alert_preferences_params
    params.require(:alert_preference).permit(
      :budget_threshold_enabled, :budget_exceeded_enabled, :spending_increase_enabled
    )
  end
end
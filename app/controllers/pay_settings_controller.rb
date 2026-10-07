# frozen_string_literal: true

# PaySettingsController
# GET/PATCH /settings/pay: the user's financial cycle configuration — the
# day of the month their financial month starts on (1..28, default 1). The
# notice shows the resulting current cycle so the effect is visible.
class PaySettingsController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    if current_user.update(financial_cycle_start_day: params.dig(:user, :financial_cycle_start_day))
      redirect_to pay_settings_path,
                  notice: t("pay_settings.saved", cycle: PayCycle.current(current_user).label)
    else
      render :show, status: :unprocessable_entity
    end
  end
end

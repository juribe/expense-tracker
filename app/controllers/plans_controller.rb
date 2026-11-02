# frozen_string_literal: true

class PlansController < ApplicationController
  before_action :authenticate_user!

  def index
    @monthly = PaymentEngine::PaymentOption.find_by(name: "Mensual")
    @annual = PaymentEngine::PaymentOption.find_by(name: "Anual")
    @can_trial = PaymentEngine::AccessPolicy.can_start_trial?(current_user)
    @settings = PaymentEngine::Setting.current
  end

  def start_trial
    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: current_user, actor: current_user)
    if result.success?
      redirect_to root_path, notice: "Tu prueba gratuita ha comenzado."
    else
      redirect_to plans_path, alert: result.errors.join(", ")
    end
  end
end

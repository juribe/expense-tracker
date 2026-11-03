# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index pricing prices precios]

  layout "home"

  # The marketing prototypes use inline styles for layout fidelity.
  content_security_policy do |policy|
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
  end

  def index
    redirect_to dashboard_path if user_signed_in?
  end

  def pricing
    @settings = PaymentEngine::Setting.current rescue nil
    @membership_type = PaymentEngine::MembershipType.active.first
    @options = PaymentEngine::PaymentOption.where(status: "active").order(:position)
    @monthly = @options.find { |o| o.name.to_s.downcase.include?("mensual") } || @options.find { |o| o.name.to_s.downcase.include?("monthly") }
    @annual = @options.find { |o| o.name.to_s.downcase.include?("anual") } || @options.find { |o| o.name.to_s.downcase.include?("annual") }
    @trial_enabled = PaymentEngine::Configuration.free_trial_enabled?
    @trial_days = PaymentEngine::Configuration.free_trial_duration_days
    @payments_enabled = PaymentEngine::Configuration.payments_enabled?
    @can_trial = @trial_enabled
  end
  alias prices pricing
  alias precios pricing
end

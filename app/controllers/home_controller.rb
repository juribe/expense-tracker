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

  def pricing; end
  alias prices pricing
  alias precios pricing
end

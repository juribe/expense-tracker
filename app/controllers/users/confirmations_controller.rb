# frozen_string_literal: true

class Users::ConfirmationsController < Devise::ConfirmationsController
  rate_limit to: 5, within: 1.minute, only: :create, store: RateLimitProxy.new

  protected

  def after_confirmation_path_for(resource_name, resource)
    if session[:trial_intent]
      # Route to plans page where user (now signed in after confirmation? confirmation doesn't sign in automatically)
      # Keep session; redirect to login? Devise confirmation signs in if allow_unconfirmed_access? no.
      new_user_session_path
    elsif session[:pending_payment_option_id]
      new_user_session_path
    else
      super
    end
  end
end

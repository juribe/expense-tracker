# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :store_commercial_intent, only: [ :new, :create ]

  # Devise's default update_resource always demands the current password,
  # even for name-only edits. Only password/e-mail changes keep the
  # confirmation; a blank password updates the remaining profile freely.
  #
  # Closing an account destroys the user and, transitively, every MoneySource.
  # Each source's `outgoing_transfers` / `incoming_transfers` associations are
  # destroyed in turn; loading them lazily per source is an N+1 that Bullet
  # flags (and raises on in development). Eager-load them up front so the
  # cascade stays a single query batch. The redirect lands on the app root
  # (the sign-in screen once signed out) instead of the meaningless /users.
  def destroy
    self.resource = User.includes(money_sources: [ :outgoing_transfers, :incoming_transfers, :goals, :payments, :credit_scenarios, :credit_extra_payments, :gmf_monthly_accumulators ]).find(resource.id)
    super
  end

  protected

  def update_resource(resource, params)
    if sensitive_change?(resource, params)
      resource.update_with_password(params)
    else
      safe_params = params.except(:password, :password_confirmation, :current_password)
      resource.update(safe_params)
    end
  end

  private

  # The registration form carries virtual consent fields. Mark the resource so
  # the model validates and records them only for this flow.
  def build_resource(hash = {})
    super
    resource.registration_form = true if action_name == "create"
  end

  # `admin` is intentionally never permitted here or in account_update_params:
  # the role is not assignable through public sign-up or profile updates.
  def sign_up_params
    params.expect(user: [
      :name,
      :email,
      :password,
      :password_confirmation,
      :terms_accepted,
      :privacy_accepted,
      :marketing_consent
    ])
  end

  def sensitive_change?(resource, params)
    email_changing = params[:email].present? && params[:email] != resource.email
    password_changing = params[:password].present? || params[:password_confirmation].present?

    email_changing || password_changing
  end

  def account_update_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :current_password)
  end

  private

  def store_commercial_intent
    session[:trial_intent] = true if params[:trial].present? || params[:trial_intent].present?
    session[:pending_payment_option_id] = params[:payment_option_id] if params[:payment_option_id].present?
  end

  protected

  def after_inactive_sign_up_path_for(resource)
    super
  end
end

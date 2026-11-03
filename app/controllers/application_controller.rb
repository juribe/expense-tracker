class ApplicationController < ActionController::Base
  helper :mailer
  # Shared page size for every paginated list (expenses, expense candidates,
  # applied payments) so pagination behaves consistently app-wide.
  PER_PAGE = 25

  include Chartkick::Helper

  layout :layout_for_request

  before_action :authenticate_user!
  before_action :set_page_title, if: -> { request.get? }
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # A stale/invalid CSRF token (e.g. a page left open across a sign-in, or a
  # Turbo-cached form) must not surface as a cryptic JSON 500: send the user
  # back with a clear "please retry" message.
  rescue_from ActionController::InvalidAuthenticityToken do
    redirect_back fallback_location: root_path,
                  alert: t("errors.csrf_retry", default: "Tu sesión cambió. Inténtalo de nuevo.")
  end

  # rescue_from StandardError do |exception|
  #   render json: { status: 'error', message: exception.message }, status: :internal_server_error
  # end

  def set_page_title
    key = "#{controller_name}-#{action_name}"
    @page_title = I18n.t("page.titles.#{key}", default: nil)
  end

  private

  # The current membership of the signed-in user for dashboards, banners and
  # plan cards.
  def current_membership
    return nil unless user_signed_in?
    PaymentEngine::Membership.where(owner: current_user).order(expires_at: :desc).first
  end
  helper_method :current_membership

  # Controls the once-per-day membership expiry banner. It is only visible
  # while the membership is active and within the five days before its
  # expiration date.
  def membership_expiry_banner?
    return false unless user_signed_in?
    membership = current_membership
    return false unless membership&.active? && membership.expires_at.present?

    days_left = (membership.expires_at.to_date - Date.current).to_i
    return false unless days_left.between?(0, 5)
    return false if cookies[:membership_expiry_banner] == Date.current.to_s

    true
  end

  def prepare_membership_expiry_banner
    return unless membership_expiry_banner?

    @show_membership_expiry_banner = true
    cookies[:membership_expiry_banner] = {
      value: Date.current.to_s,
      expires: 1.day.from_now,
      path: "/"
    }
  end

  before_action :prepare_membership_expiry_banner, if: :user_signed_in?

  # Admin-only areas redirect regular users to the dashboard instead of
  # revealing their contents.
  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: t("errors.not_authorized")
  end

  # Signed-out Devise screens (sign in/up, password recovery, confirmations)
  # use the branded auth layout. Profile management stays in the application
  # shell; the password reset action also signs the user in before rendering
  # its success state, so session state is not a reliable discriminator.
  def layout_for_request
    return "application" unless devise_controller?
    return "application" if controller_name == "registrations" && %w[edit update destroy].include?(action_name)

    "auth"
  end
end

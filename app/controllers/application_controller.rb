class ApplicationController < ActionController::Base
  # Shared page size for every paginated list (expenses, expense candidates,
  # applied payments) so pagination behaves consistently app-wide.
  PER_PAGE = 25

  include Chartkick::Helper

  layout :layout_for_request

  before_action :authenticate_user!
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

  private

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

class ApplicationController < ActionController::Base
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

  rescue_from StandardError do |exception|
    render json: { status: 'error', message: exception.message }, status: :internal_server_error
  end
end
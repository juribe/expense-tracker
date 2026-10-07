class ApplicationController < ActionController::Base
  # Shared page size for every paginated list (expenses, expense candidates,
  # applied payments) so pagination behaves consistently app-wide.
  PER_PAGE = 25

  before_action :authenticate_user!
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Default date for new records (expense/income/transfer forms): the start
  # of the current pay cycle when the user configured paydays — bills paid
  # right after payday get dated from it — otherwise plain today.
  def default_record_date
    Reports::Period.cycles_enabled?(current_user) ? PayCycle.current(current_user).starts : Date.current
  end

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
end

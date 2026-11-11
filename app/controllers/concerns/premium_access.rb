# frozen_string_literal: true

# PremiumAccess
# Declares premium-only controller actions and renders the shared lock page
# (view: shared/premium_locked) for users without access. JSON requests get a
# 403 with the premium error so API callers can react without HTML.
#
# Example:
#   require_premium
#   require_premium only: :show
#   require_premium except: :index
module PremiumAccess
  extend ActiveSupport::Concern

  class_methods do
    def require_premium(**options)
      before_action :require_premium_access, **options
    end
  end

  private

  def require_premium_access
    return if user_access.access_premium?

    handle_premium_access_denied
  end

  def handle_premium_access_denied
    respond_to do |format|
      format.html { render "shared/premium_locked" }
      format.json { render json: { error: t("errors.premium_only") }, status: :forbidden }
      format.any { head :forbidden }
    end
  end
end

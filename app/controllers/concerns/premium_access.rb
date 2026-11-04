# frozen_string_literal: true

# PremiumAccess
# Declares premium-only controller actions and blocks users without access.
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
    redirect_to dashboard_path, alert: t("errors.premium_only")
  end
end

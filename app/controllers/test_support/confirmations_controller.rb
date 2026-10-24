# frozen_string_literal: true

module TestSupport
  # Supports Playwright specs that create accounts through the sign-up form.
  # Only routed in the test environment (see config/routes.rb).
  class ConfirmationsController < ActionController::Base
    before_action :ensure_test_environment

    def create
      User.find_by(email: params[:email])&.confirm
      head :no_content
    end

    private

    def ensure_test_environment
      head :not_found unless Rails.env.test?
    end
  end
end

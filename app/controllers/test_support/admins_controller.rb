# frozen_string_literal: true

module TestSupport
  # Supports Playwright specs that need an admin to reach the internal tools
  # (expense playground and AI evaluations). Only routed in the test
  # environment (see config/routes.rb).
  class AdminsController < ActionController::Base
    before_action :ensure_test_environment

    def create
      User.find_by(email: params[:email])&.update(admin: true)
      head :no_content
    end

    private

    def ensure_test_environment
      head :not_found unless Rails.env.test?
    end
  end
end

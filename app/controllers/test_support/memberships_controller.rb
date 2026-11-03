# frozen_string_literal: true

module TestSupport
  # Grants a free trial membership to a Playwright-created account so that
  # membership gating does not block navigation in E2E specs.
  # Only routed in the test environment.
  class MembershipsController < ActionController::Base
    before_action :ensure_test_environment

    def create
      user = User.find_by(email: params[:email])
      PaymentEngine::Memberships::StartFreeTrial.call(owner: user, actor: user) if user
      head :no_content
    end

    private

    def ensure_test_environment
      head :not_found unless Rails.env.test?
    end
  end
end

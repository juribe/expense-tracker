# frozen_string_literal: true

module TestSupport
  # Sets the money tracking mode for a Playwright-created account. E2E specs
  # exercise the advanced account/card flows, so they opt into `detailed`
  # after sign-up unless a spec asks for another mode.
  # Only routed in the test environment (see config/routes.rb).
  class TrackingModesController < ActionController::Base
    before_action :ensure_test_environment

    def create
      user = User.find_by(email: params[:email])
      mode = params[:mode].presence_in(User::MONEY_TRACKING_MODES) || "detailed"
      MoneySources::ModeSwitch.new(user: user, mode: mode).call if user

      # E2E specs predate General and assume the user's own sources are the
      # only options. Keep the test account in advanced mode but remove the
      # empty conversion account so those flows stay deterministic.
      if user && mode == "detailed" && params[:keep_general].to_s != "true"
        user.money_sources.find_by(general: true)&.destroy
      end

      head :no_content
    end

    private

    def ensure_test_environment
      head :not_found unless Rails.env.test?
    end
  end
end

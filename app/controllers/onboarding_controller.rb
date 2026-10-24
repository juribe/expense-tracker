# frozen_string_literal: true

# OnboardingController
# Persists the dashboard setup banner steps the user chooses to skip
# permanently. Records never mention other users' state and nothing else is
# written here: completed/pending states are derived from real data.
#
# POST /onboarding/skip/:step  : skip one banner step permanently
# POST /onboarding/skip_all    : skip every step still pending
class OnboardingController < ApplicationController
  before_action :authenticate_user!

  def skip
    step = params.require(:step)

    unless OnboardingProgress::STEPS.include?(step)
      redirect_to dashboard_path, alert: t("onboarding.invalid_step")
      return
    end

    OnboardingProgress.for_user(current_user).skip!(step)
    redirect_to dashboard_path, notice: t("onboarding.step_skipped", step: step_title(step))
  end

  def skip_all
    pending_keys = Dashboard::Onboarding.new(user: current_user).pending_keys
    OnboardingProgress.for_user(current_user).skip_all!(pending_keys)

    redirect_to dashboard_path, notice: t("onboarding.all_skipped")
  end

  private

  def step_title(step)
    t("onboarding.steps.#{step}.title")
  end
end

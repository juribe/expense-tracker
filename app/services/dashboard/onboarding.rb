# frozen_string_literal: true

# Dashboard::Onboarding
# Derives the dashboard setup banner state for a user. A step is completed
# when its real data exists, skipped when the user skipped it permanently
# (OnboardingProgress), and pending otherwise. The banner only renders
# pending steps; skip!/skip_all! never depend on this presentation layer.
#
# Methods: call, pending_steps, pending_keys, visible?
#
# Example: Dashboard::Onboarding.new(user: current_user).pending_steps
class Dashboard::Onboarding
  STEPS = OnboardingProgress::STEPS

  Step = Data.define(:key, :completed, :skipped) do
    def pending?
      !completed && !skipped
    end
  end

  def initialize(user:)
    @user = user
  end

  def call
    @steps ||= STEPS.index_with do |key|
      Step.new(key: key, completed: completed?(key), skipped: progress.skipped?(key))
    end
  end

  def pending_steps
    call.values.select(&:pending?)
  end

  def pending_keys
    pending_steps.map(&:key)
  end

  def visible?
    pending_steps.any?
  end

  def pending_count
    pending_steps.count
  end

  # The four exists? calls (three sources of truth + the skip row) are the
  # whole state read; no per-row loading or N+1 is possible.
  def progress
    @progress ||= OnboardingProgress.for_user(@user)
  end

  private

  def completed?(step)
    case step
    when "initial" then @user.financial_setups.exists?(status: "completed")
    when "gmail" then @user.gmail_connections.active.exists?
    when "whatsapp" then @user.whatsapp_connections.active.exists?
    end
  end
end

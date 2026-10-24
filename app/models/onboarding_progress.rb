# frozen_string_literal: true

# OnboardingProgress
# Per-user state for the dashboard setup banner: the steps the user chose to
# skip permanently («Saltar» / «Saltar toda la configuración»). Whether a step
# is completed or pending is derived elsewhere from real data; only skips live
# here. «No ahora» and closing the banner never write to this table.
#
# Associations: belongs_to :user (exactly one row per user)
# Methods: skipped?, skip!, skip_all!, for_user
#
# Example: OnboardingProgress.for_user(user).skip!("gmail")
class OnboardingProgress < ApplicationRecord
  STEPS = %w[initial gmail whatsapp].freeze

  belongs_to :user

  validate :skipped_steps_are_known

  # Existing row for the banner, or a transient default one. Reading the
  # banner must not write to the database; skip!/skip_all! persist on change.
  def self.for_user(user)
    user.onboarding_progress || user.build_onboarding_progress
  end

  def skipped?(step)
    skipped_steps.include?(step.to_s)
  end

  # Persists a permanent skip for one step. Repeated calls are no-ops and
  # never touch the other steps.
  def skip!(step)
    step_key = step.to_s
    raise ArgumentError, "unknown onboarding step: #{step_key}" unless STEPS.include?(step_key)

    self.skipped_steps = skipped_steps | [ step_key ]
    save! if will_save_change_to_skipped_steps?
    self
  end

  # Persists permanent skips for several steps at once (skipping everything
  # still pending from the banner).
  def skip_all!(steps)
    steps.each { |step| skip!(step) }
    self
  end

  private

  def skipped_steps_are_known
    unknown = skipped_steps - STEPS
    errors.add(:skipped_steps, :invalid) if unknown.any?
  end
end

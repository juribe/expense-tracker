# frozen_string_literal: true

# AlertPreference
# Per-user toggles controlling which alert kinds are produced. A missing row
# means "use the defaults" (budget alerts on, spending increase off).
#
# Associations: belongs_to :user.
#
# Example: current_user.alert_prefs.budget_exceeded_enabled?
class AlertPreference < ApplicationRecord
  belongs_to :user

  validates :budget_threshold_enabled, inclusion: { in: [ true, false ] }
  validates :budget_exceeded_enabled, inclusion: { in: [ true, false ] }
  validates :spending_increase_enabled, inclusion: { in: [ true, false ] }
end
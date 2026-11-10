# frozen_string_literal: true

# Reports::Perspectives::Thresholds
# Tunable limits for the perspectives analysis. Keeping them together makes the
# report easy to calibrate without touching the detection rules.
class Reports::Perspectives::Thresholds
  MAX_FINDINGS = 6
  MAX_RECOMMENDATIONS = 3
  EVOLUTION_PERIODS = 6

  # Overall spending change that deserves a finding.
  SPENDING_CHANGE_PCT = 20.0

  # Category changes need a real monetary impact, not only a high percentage.
  CATEGORY_CHANGE_PCT = 20.0
  CATEGORY_CHANGE_MIN_AMOUNT = 100_000
  CATEGORY_CHANGE_ABSOLUTE_OVERRIDE = 1_000_000

  # A category this share of total spending is concentrated.
  CONCENTRATION_PCT = 30.0
  SOURCE_CONCENTRATION_PCT = 60.0

  # A single expense is unusual when it is this many times the category's
  # historical average transaction amount, with enough history to trust it.
  UNUSUAL_RATIO = 2.5
  UNUSUAL_MIN_AMOUNT = 500_000
  UNUSUAL_MIN_HISTORY = 3

  # Recurring payments must represent a meaningful part of period spending.
  RECURRING_MIN_SHARE_PCT = 10.0
  RECURRING_LOOKBACK_MONTHS = 6

  # A spending reduction accompanied by a large drop in recorded transactions
  # is more likely a recording gap than a real improvement.
  LOW_RECORDING_RATIO = 0.5
end

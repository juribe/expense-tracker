# frozen_string_literal: true

# Reports::Thresholds
# Configurable thresholds for the deterministic insights engine. Change values
# here (or override in an initializer) rather than editing the rules; every
# threshold is tuned to avoid noisy insights.
#
# Example: Reports::Thresholds::MAX_INSIGHTS # => 4
class Reports::Thresholds
  MAX_INSIGHTS = 4

  # Percentage rise versus the previous equivalent period that triggers an
  # insight (total spending and per-category).
  SPENDING_SPIKE_PCT = 20.0
  CATEGORY_SPIKE_PCT = 25.0
  DEBT_PAYMENT_SPIKE_PCT = 25.0

  # Ratio over the 6-month historical average that reads as "unusual", and
  # the minimum months with activity required before trusting that average.
  CATEGORY_AVERAGE_RATIO = 1.5
  CATEGORY_AVERAGE_MIN_MONTHS = 3

  # A single transaction is an outlier when it exceeds this ratio of the
  # period average and is at least this absolute amount.
  LARGE_TRANSACTION_RATIO = 3.0
  LARGE_TRANSACTION_MIN = 1_000_000

  # Transactions count in the period versus the historical monthly average.
  TRANSACTION_COUNT_RATIO = 2.0

  # Credit utilization considered high, and the jump in utilization points.
  HIGH_UTILIZATION_PCT = 50.0
  CREDIT_UTILIZATION_JUMP_PCT = 10.0

  # Growth in recurring commitments versus last month's processed recurring.
  RECURRING_INCREASE_PCT = 5.0
end

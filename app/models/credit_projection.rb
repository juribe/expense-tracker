# frozen_string_literal: true

# CreditProjection
# Persisted informational projection of a loan's finances (schedule, summary,
# assumptions), built from existing credit/payment data plus user-entered
# estimates. One row per money source; never writes back to the credit.
#
# Associations: belongs_to :money_source
# Methods: stale?, future_rows, past_rows, needs_review?, deviations, current_fingerprint
#
# Example: Credits::Projection::Builder.call(loan) → projection.refresh!
class CreditProjection < ApplicationRecord
  belongs_to :money_source

  validates :fingerprint, presence: true

  def self.current_fingerprint_parts(money_source)
    payments = money_source.payments
    [
      money_source.updated_at.to_f,
      money_source.credit_account&.updated_at.to_f,
      payments.maximum(:updated_at).to_f,
      payments.maximum(:id).to_i,
      payments.count
    ]
  end

  def stale?
    fingerprint != self.class.current_fingerprint_parts(money_source.reload).join(":")
  end

  def future_rows
    schedule["future"] || []
  end

  def past_rows
    schedule["past"] || []
  end

  def estimated?
    estimated
  end

  def needs_review?
    summary["needs_review"].present?
  end

  def deviations
    summary["deviations"] || []
  end
end

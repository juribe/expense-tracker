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
    extras = money_source.credit_extra_payments
    [
      money_source.updated_at.to_f,
      money_source.credit_account&.updated_at.to_f,
      payments.maximum(:updated_at).to_f,
      Digest::MD5.hexdigest(payments.order(:created_at, :id).pluck(:id).join(",")),
      payments.count,
      extras.maximum(:updated_at).to_f,
      extras.count
    ]
  end

  def stale?
    fingerprint != self.class.current_fingerprint_parts(money_source.reload).join(":") || legacy_assumptions?
  end

  # Assumptions became { "label" =>, "value" => } pairs in a later format; a row
  # still holding plain sentences is rebuilt so the view can label each value.
  def legacy_assumptions?
    assumptions.any? && !assumptions.first.is_a?(Hash)
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

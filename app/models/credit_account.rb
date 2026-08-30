# frozen_string_literal: true

# CreditAccount
# Credit/debt-specific details for a MoneySource (credit cards and loans),
# kept separate from generic MoneySource data.
#
# Associations: belongs_to :money_source (one per source)
# Methods: interest_rate_label, rate_type_label
#
# Example: source.credit_account.credit_limit
class CreditAccount < ApplicationRecord
  CARD_BRANDS = %w[visa mastercard amex other].freeze

  INTEREST_RATE_TYPES = {
    effective_annual: "effective_annual",
    nominal_annual: "nominal_annual",
    monthly: "monthly"
  }.freeze

  PAYMENT_FREQUENCIES = %w[weekly biweekly monthly quarterly].freeze

  belongs_to :money_source

  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :interest_rate_type, inclusion: { in: INTEREST_RATE_TYPES.values }, allow_blank: true
  validates :card_last_four, format: { with: /\A\d{4}\z/ }, allow_blank: true
  validates :card_brand, inclusion: { in: CARD_BRANDS }, allow_blank: true
  validates :statement_day, :payment_due_day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 31 }, allow_blank: true
  validates :principal_amount, :outstanding_balance, :installment_amount,
            numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
  validates :installment_count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_blank: true
  validates :payment_frequency, inclusion: { in: PAYMENT_FREQUENCIES }, allow_blank: true

  validate :valid_loan_date_range

  def interest_rate_label
    return nil if interest_rate.blank?

    suffix = rate_type_suffix(interest_rate_type)
    suffix ? format("%<rate>.2f%% %<suffix>s", rate: interest_rate, suffix: suffix) : rate_number_label
  end

  private

  def valid_loan_date_range
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, :after_start) if end_date < start_date
  end

  def rate_type_suffix(type)
    case type
    when "effective_annual" then "EA"
    when "nominal_annual" then "NA"
    when "monthly" then "M"
    end
  end

  def rate_number_label
    format("%<rate>.2f%%", rate: interest_rate)
  end
end

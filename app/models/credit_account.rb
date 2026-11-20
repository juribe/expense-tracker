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
  validates :installments_paid, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_blank: true
  validates :payment_frequency, inclusion: { in: PAYMENT_FREQUENCIES }, allow_blank: true
  validates :interest_calculation_day,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 31 },
            allow_blank: true

  validate :valid_loan_date_range

  before_validation :default_loan_payment_frequency, on: :create
  before_validation :default_interest_calculation_day
  before_validation :normalize_interest_calculation_day

  def interest_rate_label
    return nil if interest_rate.blank?

    suffix = rate_type_suffix(interest_rate_type)
    suffix ? format("%<rate>.2f%% %<suffix>s", rate: interest_rate, suffix: suffix) : rate_number_label
  end

  private

  # New loans are monthly unless a frequency was configured explicitly. The
  # form no longer offers the setting; existing weekly/biweekly/quarterly rows
  # keep working untouched.
  def default_loan_payment_frequency
    return unless money_source&.loan?

    self.payment_frequency = "monthly" if payment_frequency.blank?
  end

  # The monthly reference starts from the loan's first payment date when the
  # user has not chosen a day yet. Existing choices are never overwritten.
  def default_interest_calculation_day
    return if interest_calculation_day.present? || start_date.blank?

    self.interest_calculation_day = [ start_date.day, 30 ].min
  end

  # A 31st reference is treated as the 30th; shorter months clamp later.
  def normalize_interest_calculation_day
    self.interest_calculation_day = 30 if interest_calculation_day == 31
  end

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

# frozen_string_literal: true

class RecurringTemplate < ApplicationRecord
  TRANSACTION_TYPES = %w[income expense].freeze

  include Reconciliation::Invalidatable

  belongs_to :user
  belongs_to :category
  belongs_to :money_source, optional: true
  has_many :transactions, dependent: :nullify

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :kind, presence: true, inclusion: { in: %w[income expense] }
  validates :frequency, presence: true
  validates :source, presence: true
  validates :payment_day,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 31 },
            allow_nil: true
  validate :category_belongs_to_user
  validate :money_source_belongs_to_user

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :active, -> { where(active: true) }
  scope :income, -> { where(kind: "income") }
  scope :expense, -> { where(kind: "expense") }
  scope :ordered, -> { order(:payment_day, :id) }

  before_validation :normalize_kind
  before_validation :normalize_source
  before_validation :normalize_amount

  def income?
    kind == "income"
  end

  def expense?
    kind == "expense"
  end

  def signed_amount
    expense? ? -amount.abs : amount.abs
  end

  def last_occurrence
    transactions.order(date: :desc, created_at: :desc).first
  end

  def paid_amount_for_period(period)
    transactions.where(date: period_range(period)).sum { |transaction| transaction.amount.to_d.abs }
  end
  alias_method :amount_paid_for_period, :paid_amount_for_period
  alias_method :paid_so_far_for_period, :paid_amount_for_period

  def fully_paid_for_period?(period)
    return false unless active?

    range = period_range(period)
    transactions_in_period = transactions.where(date: range)
    return true if transactions_in_period.where(recurring_paid_in_full: true).exists?

    paid_amount_for_period(range) >= amount.to_d
  end
  alias_method :paid_for_period?, :fully_paid_for_period?
  alias_method :completed_for_period?, :fully_paid_for_period?

  def processed_for_period?(period)
    fully_paid_for_period?(period)
  end

  def has_payment_for_period?(period)
    transactions.where(date: period_range(period)).exists?
  end

  def status_for(period = Date.current.strftime("%Y-%m"))
    return :inactive unless active?
    return :completed if fully_paid_for_period?(period)

    :pending
  end

  def action_label
    income? ? I18n.t("monthly_incomes.receive") : I18n.t("monthly_expenses.pay", default: "Pagar")
  end

  def completed_action_label
    income? ? I18n.t("monthly_incomes.received") : I18n.t("monthly_expenses.paid", default: "Pagado")
  end

  def past_action_label
    income? ? I18n.t("recurring.last_received") : I18n.t("monthly_expenses.last_paid", default: "Último pago")
  end

  private

  def normalize_kind
    self.kind = kind.to_s.downcase.presence
  end

  def normalize_source
    self.source = source.to_s.downcase.presence || "manual"
  end

  def normalize_amount
    return if amount.nil?

    self.amount = amount.to_s.delete(",").to_d.abs
  end

  # Shared categories carry no owner (defaults) and belong to both scopes:
  # a foreign custom category would leak the other account's data here.
  def category_belongs_to_user
    return if user_id.nil? || category.nil? || category.user_id.nil?
    return if category.user_id == user_id

    errors.add(:category, :other_user)
  end

  # Only the owner's sources may be remembered: processing the template
  # would otherwise route the transaction at a foreign account.
  def money_source_belongs_to_user
    return if user_id.nil? || money_source.nil?
    return if money_source.user_id == user_id

    errors.add(:money_source, :other_user)
  end

  # Periods come in three shapes: a pay cycle (PayCycle::Cycle), an explicit
  # date range, or the legacy "YYYY-MM" string used by calendar-month lists.
  def period_range(period)
    return period.to_range if period.is_a?(PayCycle::Cycle)
    return period if period.is_a?(Range)

    period_range_from_period_string(period)
  end

  def period_range_from_period_string(period)
    year, month = period.to_s.split("-").map(&:to_i)
    date = Date.new(year, month, 1)
    date.beginning_of_month..date.end_of_month
  rescue ArgumentError, TypeError
    Date.current.beginning_of_month..Date.current.end_of_month
  end
end

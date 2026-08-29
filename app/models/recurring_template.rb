# frozen_string_literal: true

class RecurringTemplate < ApplicationRecord
  TRANSACTION_TYPES = %w[income expense].freeze

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

  def processed_for_period?(period)
    range = period_range(period)
    transactions.where(date: range).exists?
  end

  def status_for(period = Date.current.strftime("%Y-%m"))
    return :inactive unless active?
    return :completed if processed_for_period?(period)

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

  def period_range(period)
    year, month = period.to_s.split("-").map(&:to_i)
    date = Date.new(year, month, 1)
    date.beginning_of_month..date.end_of_month
  rescue ArgumentError, TypeError
    Date.current.beginning_of_month..Date.current.end_of_month
  end
end

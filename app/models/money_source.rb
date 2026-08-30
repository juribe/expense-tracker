# frozen_string_literal: true

# MoneySource
# Common financial-source entity (account, debit_card, credit_card, cash,
# wallet, loan). Credit/debt-specific details live on a CreditAccount.
#
# Associations: belongs_to :user/parent, has_many children/tags/transactions/
#   recurring_templates/outgoing_transfers/incoming_transfers, has_one :credit_account
# Methods: balance, used_credit, available_credit, debt?, credit_card?, loan?
#
# Example: source.used_credit
class MoneySource < ApplicationRecord
  KINDS = %w[account debit_card credit_card cash wallet loan].freeze

  belongs_to :user
  belongs_to :parent, class_name: "MoneySource", optional: true
  has_many :children, class_name: "MoneySource", foreign_key: :parent_id, dependent: :nullify
  has_many :tags, class_name: "MoneySourceTag", dependent: :destroy
  has_many :transactions, dependent: :nullify
  has_many :recurring_templates, dependent: :nullify
  has_many :outgoing_transfers, class_name: "Transfer", foreign_key: :from_source_id, dependent: :destroy
  has_many :incoming_transfers, class_name: "Transfer", foreign_key: :to_source_id, dependent: :destroy
  has_one :credit_account, dependent: :destroy

  accepts_nested_attributes_for :credit_account, allow_destroy: true

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :starting_balance, numericality: true

  scope :active, -> { where(active: true) }
  scope :by_kind, ->(kind) { where(kind: kind) }
  scope :with_tag, ->(value) {
    joins(:tags).where(tags: { value: MoneySourceTag.normalize(value) }).where(active: true).distinct
  }

  before_validation :normalize_kind

  def balance
    base = starting_balance.to_d

    tx_sum = transactions.sum(:amount).to_d
    card_tx_sum = children.map(&:transactions_amount_sum).sum.to_d

    tx_out = outgoing_transfers.sum(:amount).to_d
    tx_in = incoming_transfers.sum(:amount).to_d

    base + tx_sum + card_tx_sum - tx_out + tx_in
  end

  def transactions_amount_sum
    transactions.sum(:amount).to_d
  end

  def credit_card?
    kind == "credit_card"
  end

  def loan?
    kind == "loan"
  end

  def debit_card?
    kind == "debit_card"
  end

  def debt?
    credit_card? || loan?
  end

  def credit_account?
    credit_account.present?
  end

  # Positive magnitude of what is owed. balance returns the negative for debt
  # sources so existing debt-means-negative rendering stays consistent.
  def used_credit
    return 0 unless debt?

    [ -balance, 0 ].max
  end

  def outstanding_balance
    return nil unless loan?

    credit_account&.outstanding_balance || credit_account&.principal_amount
  end

  def credit_limit
    credit_account&.credit_limit
  end

  def available_credit
    return nil if credit_limit.to_i <= 0

    [ credit_limit - used_credit, 0 ].max
  end

  def credit_utilization
    return 0 if credit_limit.to_i <= 0

    (used_credit / credit_limit.to_d * 100).round(1)
  end

  delegate :principal_amount, :installment_amount, :installment_count,
           :payment_frequency, :statement_day, :payment_due_day,
           :interest_rate, :interest_rate_type, :card_brand, :card_last_four,
           :start_date, :end_date, :interest_rate_label,
           to: :credit_account, allow_nil: true

  def remaining_installments
    return nil if installment_count.nil? || principal_amount.to_i <= 0 || outstanding_balance.nil?

    (installment_count * (outstanding_balance / principal_amount.to_d)).round
  end

  def repayment_progress
    return 0 if principal_amount.to_i <= 0 || outstanding_balance.nil?

    (outstanding_balance / principal_amount.to_d * 100).round(1)
  end

  def balance_label
    if debit_card? && parent
      "→ #{parent.name}"
    else
      ActionController::Base.helpers.number_to_currency(balance)
    end
  end

  def display_name
    parts = [ name ]
    parts << bank if bank.present?
    parts << card_last_four if credit_card? && card_last_four.present?
    parts.join(" · ")
  end

  private

  def normalize_kind
    self.kind = kind.to_s.downcase if kind.present?
  end
end

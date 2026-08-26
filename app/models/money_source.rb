# frozen_string_literal: true

class MoneySource < ApplicationRecord
  KINDS = %w[account debit_card credit_card cash wallet].freeze

  belongs_to :user
  belongs_to :parent, class_name: "MoneySource", optional: true
  has_many :children, class_name: "MoneySource", foreign_key: :parent_id, dependent: :nullify
  has_many :identifiers, class_name: "MoneySourceIdentifier", dependent: :destroy
  has_many :transactions, dependent: :nullify
  has_many :recurring_templates, dependent: :nullify
  has_many :outgoing_transfers, class_name: "Transfer", foreign_key: :from_source_id, dependent: :destroy
  has_many :incoming_transfers, class_name: "Transfer", foreign_key: :to_source_id, dependent: :destroy

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :starting_balance, presence: true, numericality: true

  scope :active, -> { where(active: true) }
  scope :by_kind, ->(kind) { where(kind: kind) }

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

  def debit_card?
    kind == "debit_card"
  end

  def balance_label
    if debit_card? && parent
      "→ #{parent.name}"
    elsif credit_card?
      ActionController::Base.helpers.number_to_currency(balance)
    else
      ActionController::Base.helpers.number_to_currency(balance)
    end
  end

  def display_name
    parts = [ name ]
    parts << bank if bank.present?
    parts.join(" · ")
  end

  private

  def normalize_kind
    self.kind = kind.to_s.downcase if kind.present?
  end
end

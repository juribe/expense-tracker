# frozen_string_literal: true

class Transfer < ApplicationRecord
  include Reconciliation::Invalidatable

  belongs_to :user
  belongs_to :from_source, class_name: "MoneySource"
  belongs_to :to_source, class_name: "MoneySource"

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :different_sources
  validate :sources_belong_to_user
  validate :pocket_flow_rules
  validate :from_pocket_cannot_break_allocations
  # Manual transfers, cash withdrawals and pocket assignments must not leave
  # the origin without balance. Moving money INTO a debt is that debt's
  # payment (Payments::Apply, ExtraPayments) and is never blocked, and debt
  # origins (card advances, revolving disbursements) are never guarded.
  validate :ensure_sufficient_origin_balance, on: :create,
           if: -> { from_source.present? && to_source.present? }
  before_destroy :validate_pocket_coverage_on_reverse

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :recent, ->(limit = 20) { order(date: :desc, created_at: :desc).limit(limit) }

  # Keeps both ends' cached balances in sync: a transfer removes money from
  # the origin and adds it to the destination. A transfer into a debt IS
  # that debt's payment, so the debt's own numbers move too: a credit card
  # rides its cached balance (the debt-means-negative number), while a
  # revolving loan's debt lives on credit_account.outstanding_balance and
  # must be lowered through MoneySources::OutstandingSync like its usage
  # transactions raise it. A transfer OUT of a revolving loan is that
  # line's disbursement (crédito rotativo), so the same number is raised
  # from the origin side — and restored when the transfer is destroyed.
  after_commit on: [ :create ] do
    MoneySources::BalanceSync.adjust!(from_source, -amount.to_d)
    MoneySources::BalanceSync.adjust!(to_source, amount.to_d)
    MoneySources::OutstandingSync.adjust!(from_source, amount.to_d)
    MoneySources::OutstandingSync.adjust!(to_source, -amount.to_d)
  end

  after_commit on: [ :destroy ] do
    MoneySources::BalanceSync.adjust!(from_source, amount.to_d)
    MoneySources::BalanceSync.adjust!(to_source, -amount.to_d)
    MoneySources::OutstandingSync.adjust!(from_source, -amount.to_d)
    MoneySources::OutstandingSync.adjust!(to_source, amount.to_d)
  end

  private

  def different_sources
    return if from_source_id.blank? || to_source_id.blank?

    errors.add(:to_source, I18n.t("validation.transfer_sources")) if from_source_id == to_source_id
  end

  # Both ends must belong to the transfer's owner: the after_commit hooks
  # mutate their cached balances.
  def sources_belong_to_user
    return if user_id.nil?

    errors.add(:from_source, :other_user) if from_source && from_source.user_id != user_id
    errors.add(:to_source, :other_user) if to_source && to_source.user_id != user_id
  end

  # Manual origin guard: the transfer (or withdraw) may consume up to the
  # origin's whole available balance, never more. The balance owner follows
  # the debit-card roll-up. Payments into a debt stay free: that is how the
  # app registers card and revolving payments.
  def ensure_sufficient_origin_balance
    owner = from_source.balance_guard_source
    return unless owner.balance_guarded?
    return if to_source.debt?

    missing = amount.to_d - owner.balance
    add_insufficient_balance_error(owner, missing) if missing.positive?
  end

  # Shared manual-guard message: names the balance owner, its available
  # balance and the exact missing amount (i18n: activerecord.errors.messages).
  def add_insufficient_balance_error(owner, missing)
    errors.add(:amount, :insufficient_balance,
               source_name: owner.name,
               available: MoneyFormat.currency(owner.balance),
               missing: MoneyFormat.currency(missing))
  end

  # Pockets move assigned money (Account → Pocket to assign, Pocket →
  # Account to release, Pocket → Pocket to re-assign). A pocket can never
  # pay a debt directly — the money must return to a real account first,
  # and debt payments there become a Payment, not a plain transfer.
  def pocket_flow_rules
    return if from_source.nil? || to_source.nil?
    return unless from_source.pocket? || to_source.pocket?

    errors.add(:to_source, :pocket_flow) if to_source.debt? || from_source.debt?
  end

  # Moving money out of a pocket must leave its goal reservations covered:
  # the remaining balance has to stay >= what is allocated to goals.
  def from_pocket_cannot_break_allocations
    return if from_source.nil? || amount.nil?
    return unless from_source.pocket?

    remaining = from_source.balance - amount.to_d
    if remaining < from_source.allocated_amount
      errors.add(:amount, :pocket_allocations_exceed_balance)
    end
  end

  # Destroying reverses the movement: a transfer that fed a pocket takes its
  # money out again. That must never leave goal reservations uncovered.
  def validate_pocket_coverage_on_reverse
    return unless to_source&.pocket?
    return if (to_source.balance - amount.to_d) >= to_source.allocated_amount

    errors.add(:base, I18n.t("activerecord.errors.messages.pocket_reverse_would_break_allocations"))
    throw(:abort)
  end
end

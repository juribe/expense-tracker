# frozen_string_literal: true

class Transaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  include Reconciliation::Invalidatable

  # Set by the AI-entry confirm flow when the user explicitly picked a
  # category; rules then never override it.
  attr_accessor :category_locked_by_user

  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :recurring_template, optional: true
  belongs_to :money_source, optional: true, counter_cache: true
  has_many :processed_emails, foreign_key: :expense_id, dependent: :nullify
  has_many :payments, class_name: "Payment", foreign_key: :expense_id, dependent: :destroy
  has_many :expense_candidates, class_name: "ExpenseCandidate", foreign_key: :expense_id, dependent: :destroy

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true
  validates :kind, presence: true, inclusion: { in: %w[income expense] }
  validates :source, presence: true
  validate :money_source_must_be_present
  validate :category_type_matches_kind, on: :create

  # Manual web-form expenses must not leave the balance owner negative: the
  # operation is rejected with the available balance and the missing amount.
  # Every other source (gmail, statement_file, whatsapp, ai, recurring
  # templates, wizard...) registers regardless of balance — a real detected
  # expense is never blocked, and the resulting temporary negative balance is
  # warned about instead. Debt sources (credit cards, loans) are never
  # guarded: their negative balance IS the debt.
  validate :ensure_sufficient_balance_for_manual_expense, on: :create,
           if: -> { expense? && money_source_id? && source == "manual" }

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :in_month, ->(date) { where(date: date.beginning_of_month..date.end_of_month) }
  scope :recent, ->(limit = 5) { order(date: :desc, created_at: :desc).limit(limit) }
  scope :income, -> { where(kind: "income") }
  scope :expense, -> { where(kind: "expense") }

  before_validation :normalize_kind
  before_validation :normalize_source
  before_validation :normalize_amount
  before_validation :normalize_signed_amount
  before_validation :apply_automatic_rules, on: :create

  # Spending alerts fire only for expenses, after the write commits, so the
  # engine sees a stable spend value and re-evaluates on every write path
  # (manual, bulk, gmail, recurring). Transfers are a separate model and never
  # reach this hook, so they are excluded structurally.
  after_commit on: [ :create ], if: :expense? do
    SpendingAlertService.call(user: user, category: category, month: date)
  end

  after_commit on: [ :update ], if: :expense? do
    SpendingAlertService.call(user: user, category: category, month: date)
    if saved_change_to_date?
      SpendingAlertService.call(user: user, category: category, month: date_before_last_save)
    end
  end

  after_commit on: [ :destroy ], if: :expense? do
    SpendingAlertService.call(user: user, category: category, month: date)
  end

  # Keeps the owning money source's cached balance in sync. The delta equals
  # the signed amount already normalized by normalize_signed_amount, so the
  # same routing works for expenses and incomes. Revolving loans additionally
  # move credit_account.outstanding_balance: usage raises the debt, the same
  # number Payments lower.
  after_commit on: [ :create ], if: :money_source_id? do
    MoneySources::BalanceSync.adjust!(money_source, amount.to_d)
    MoneySources::OutstandingSync.adjust!(money_source, -amount.to_d)
  end

  after_commit on: [ :update ], if: :balance_relevant_change? do
    old_source_id = saved_change_to_money_source_id? ? money_source_id_before_last_save : money_source_id_was
    old_source = old_source_id && MoneySource.find_by(id: old_source_id)
    MoneySources::BalanceSync.adjust!(old_source, -amount_before_last_save.to_d)
    MoneySources::OutstandingSync.adjust!(old_source, amount_before_last_save.to_d)

    MoneySources::BalanceSync.adjust!(money_source, amount.to_d)
    MoneySources::OutstandingSync.adjust!(money_source, -amount.to_d)
  end

  after_commit on: [ :destroy ], if: :money_source_id? do
    MoneySources::BalanceSync.adjust!(money_source, -amount.to_d)
    MoneySources::OutstandingSync.adjust!(money_source, amount.to_d)
  end

  private

  def category_type_matches_kind
    return if category.nil? || category.category_type.blank?
    return if category.category_type == kind
    errors.add(:category_id, I18n.t("validation.category_type_mismatch"))
  end

  # Every real movement owns its origin: expenses leave from a source,
  # incomes arrive to one. Recurring templates are reminders and stay
  # optional; this rule governs the transactions that move balances.
  def money_source_must_be_present
    return if money_source_id.present?

    errors.add(:money_source, :money_source_required)
  end

  def balance_relevant_change?
    (saved_changes.keys & %w[amount money_source_id]).any?
  end

  # Manual expense guard: spend = |amount| against the available balance of
  # the balance owner (a debit card spends its parent account, like
  # BalanceSync). Spending up to the balance is allowed (balance ends at 0);
  # anything above it is rejected. No operation is saved when it violates
  # the rule.
  def ensure_sufficient_balance_for_manual_expense
    owner = money_source.balance_guard_source
    return if owner.debt?

    missing = amount.to_d.abs - owner.balance
    add_insufficient_balance_error(owner, missing) if missing.positive?
  end

  # Shared manual-guard message: names the balance owner, its available
  # balance and the exact missing amount (i18n: activerecord.errors.messages).
  def add_insufficient_balance_error(owner, missing)
    errors.add(:money_source, :insufficient_balance,
               source_name: owner.name,
               available: MoneyFormat.currency(owner.balance),
               missing: MoneyFormat.currency(missing))
  end

  def normalize_kind
    self.kind = kind.to_s.downcase if kind.present?
    self.kind = self.class.name.underscore if kind.blank? && self.class != Transaction
  end

  def normalize_source
    self.source = source.to_s.downcase.presence || "manual"
  end

  def normalize_amount
    return if amount.nil?

    self.amount = amount.to_s.delete(",")
  end

  def normalize_signed_amount
    return if amount.blank? || kind.blank?

    normalized_amount = amount.to_s.delete(",").to_d.abs
    self.amount = kind == "expense" ? -normalized_amount : normalized_amount
  rescue ArgumentError, TypeError
    nil
  end

  public

  def transaction_date
    date
  end

  def expense?
    kind == "expense"
  end

  def signed_amount
    amount
  end

  def tags
    self[:tags] || []
  end

  def add_tag(tag_name)
    return if tag_name.blank?
    return if tags.include?(tag_name)

    self[:tags] = tags + [ tag_name ]
  end

  private

  # Applies the user's automatic rules once, at creation time only. Rules fill
  # gaps (blank category, unset money source, missing tag) and never overwrite
  # explicit values. AI-entry expenses are the exception: the parser's category
  # is a guess, so a matching rule takes precedence. Gated behind a cheap
  # existence check so rule-free manual entries pay almost nothing.
  def apply_automatic_rules
    return unless new_record?
    return if applied_rule_ids.any?
    return unless TransactionRule.active.for_user(user).exists?

    TransactionRules::Applicator.new(user).apply(self, prefer_rules: source == "ai" && !category_locked_by_user)
  end
end

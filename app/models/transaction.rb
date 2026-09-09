# frozen_string_literal: true

class Transaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  # Set by the AI-entry confirm flow when the user explicitly picked a
  # category; rules then never override it.
  attr_accessor :category_locked_by_user

  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :recurring_template, optional: true
  belongs_to :money_source, optional: true
  has_many :processed_emails, foreign_key: :expense_id, dependent: :destroy

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true
  validates :kind, presence: true, inclusion: { in: %w[income expense] }
  validates :source, presence: true

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

  private

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

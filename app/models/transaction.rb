# frozen_string_literal: true

class Transaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  belongs_to :user
  belongs_to :category
  belongs_to :recurring_template, optional: true
  belongs_to :money_source, optional: true

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

  def signed_amount
    amount
  end
end

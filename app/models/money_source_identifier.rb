# frozen_string_literal: true

class MoneySourceIdentifier < ApplicationRecord
  belongs_to :money_source

  KINDS = %w[card_last_four bank_name account_number].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :value, presence: true
  validates :value, uniqueness: { scope: :kind }
  validate :parent_must_be_active

  before_validation :normalize_value

  scope :by_kind, ->(kind) { where(kind: kind) }

  private

  def normalize_value
    return if value.blank?

    case kind
    when "card_last_four"
      digits = value.to_s.gsub(/[^0-9]/, "")
      self.value = digits.last(4)
    when "bank_name"
      self.value = value.to_s.strip.downcase
    when "account_number"
      self.value = value.to_s.strip.gsub(/[^0-9]/, "")
    end
  end

  def parent_must_be_active
    return unless money_source && !money_source.active?

    errors.add(:money_source, "must be active")
  end
end

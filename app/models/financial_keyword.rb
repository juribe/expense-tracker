# frozen_string_literal: true

# Global financial email keyword (seeded from db/seed_data). Category drives
# the signal weight used by SourceRecognition::FinancialEmailFilter.
class FinancialKeyword < ApplicationRecord
  CATEGORIES = %w[transactions cards loans status security].freeze

  validates :value, presence: true, uniqueness: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :weight, numericality: { only_integer: true, greater_than: 0 }

  # Word categories that indicate money movement (as opposed to cards,
  # loans or security words which alone do not make an email transactional).
  def transactional? = category.in?(%w[transactions loans status])
end

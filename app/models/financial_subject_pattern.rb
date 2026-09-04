# frozen_string_literal: true

# Generic subject pattern that signals a financial notification email
# (seeded from db/seed_data). Patterns are contained-match signals, never
# exact-match requirements.
class FinancialSubjectPattern < ApplicationRecord
  validates :value, presence: true, uniqueness: true
  validates :weight, numericality: { only_integer: true, greater_than: 0 }
end

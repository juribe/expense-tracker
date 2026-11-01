# frozen_string_literal: true

# GmfMonthlyAccumulator
# Persisted monthly aggregate of movements that consume the GMF exemption
# for a single MoneySource. Periods are calendar months (year/month), never
# the user's financial cycle.
#
# Associations: belongs_to :user, belongs_to :money_source
# Methods: .for(user:, money_source:, date:)
#
# Example: GmfMonthlyAccumulator.for(user: u, money_source: ms, date: Date.current)
class GmfMonthlyAccumulator < ApplicationRecord
  belongs_to :user
  belongs_to :money_source

  validates :year, presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :user_id, presence: true
  validates :money_source_id, presence: true

  # Finds or creates the accumulator row for the calendar month of `date`.
  def self.for(user:, money_source:, date:)
    date = date.to_date
    find_or_create_by!(user: user, money_source: money_source, year: date.year, month: date.month)
  end
end

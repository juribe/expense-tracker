# frozen_string_literal: true

# GmfUvtYear
# Centralized annual UVT (Unidad de Valor Tributario) values used to compute
# the monthly GMF exemption limit (350 * UVT of the movement's year).
#
# Associations: none
# Methods: .value_for(year), .exemption_limit(year)
#
# Example: GmfUvtYear.value_for(2026) # => BigDecimal("49799")
class GmfUvtYear < ApplicationRecord
  self.primary_key = :year

  validates :year, presence: true, uniqueness: true
  validates :value, presence: true, numericality: { greater_than: 0 }

  # Returns the UVT value for the given year, falling back to the latest
  # available year when the requested one is not seeded yet.
  def self.value_for(year)
    year = year.to_i
    record = find_by(year: year)
    record ||= order(year: :desc).first
    raise ArgumentError, "no UVT value seeded" unless record

    record.value.to_d
  end

  def self.exemption_limit(year)
    value_for(year) * 350
  end
end

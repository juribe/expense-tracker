# frozen_string_literal: true

class MoneySourceTag < ApplicationRecord
  belongs_to :money_source

  validates :value, presence: true
  validates :value, uniqueness: { scope: :money_source_id }

  before_validation :normalize_value

  class << self
    def normalize(value)
      value.to_s.strip.downcase
    end

    # Returns the active MoneySources whose tags match the given value.
    # Uses the same normalization as storing, so lookups are exact but
    # case/whitespace-insensitive.
    def matching(value)
      MoneySource.active.joins(:tags).where(tags: { value: normalize(value) }).distinct
    end
  end

  private

  def normalize_value
    self.value = self.class.normalize(value)
  end
end

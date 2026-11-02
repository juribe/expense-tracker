# frozen_string_literal: true

module PaymentEngine
  class PaymentOption < ApplicationRecord
    belongs_to :membership_type

    validates :name, presence: true
    validates :price, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, presence: true
    validates :mode, inclusion: { in: %w[one_time recurring] }
    validates :interval, inclusion: { in: %w[day month year] }, allow_nil: true
    validates :interval_count, numericality: { greater_than: 0 }, allow_nil: true
    validates :access_duration_count, numericality: { greater_than: 0 }
    validates :access_duration_unit, inclusion: { in: %w[day month year] }

    validate :recurrence_fields_consistency

    scope :active, -> { where(status: "active") }

    def one_time?; mode == "one_time"; end

    def access_duration
      count = access_duration_count.to_i
      unit = access_duration_unit.to_s
      case unit
      when "day" then count.days
      when "month" then count.months
      when "year" then count.years
      else count.days
      end
    end

    def recurring?; mode == "recurring"; end

    private

    def recurrence_fields_consistency
      if recurring?
        errors.add(:interval, :blank) if interval.blank?
        errors.add(:interval_count, :blank) if interval_count.blank?
      else
        # one_time: ignore recurrence
      end
    end
  end
end

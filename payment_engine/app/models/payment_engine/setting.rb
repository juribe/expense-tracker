# frozen_string_literal: true

module PaymentEngine
  class Setting < ApplicationRecord
    validates :free_trial_duration_days, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }
    self.table_name = "payment_engine_settings"

    def self.current
      first || create!(free_trial_duration_days: 60)
    end

    def trial_duration_days
      free_trial_duration_days
    end
  end
end

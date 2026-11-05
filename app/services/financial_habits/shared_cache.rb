# frozen_string_literal: true

module FinancialHabits
  module SharedCache
    module_function

    def store
      @store ||= if Rails.env.development?
        ActiveSupport::Cache::FileStore.new(
          Rails.root.join("tmp/cache/financial_habits"),
          expires_in: 1.day
        )
      else
        Rails.cache
      end
    end
  end
end
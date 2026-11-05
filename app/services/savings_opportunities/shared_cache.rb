# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::SharedCache
  # Cross-process cache for the background analysis. Development uses an
  # in-memory store by default, which is private to each process, so the job
  # worker could never publish its result to the web process. FileStore is
  # shared by the web and worker processes in development; production keeps the
  # application's Solid Cache store.
  #
  # Methods: store
  #
  # Example: SavingsOpportunities::SharedCache.store.read("key")
  module SharedCache
    module_function

    def store
      @store ||= if Rails.env.development?
        ActiveSupport::Cache::FileStore.new(
          Rails.root.join("tmp/cache/savings_opportunities"),
          expires_in: 1.day
        )
      else
        Rails.cache
      end
    end
  end
end

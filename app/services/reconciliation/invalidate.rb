# frozen_string_literal: true

module Reconciliation
  # Marks persisted reconciliation states stale so the next visit (or the
  # explicit Refresh action) recalculates instead of trusting old counts.
  # Pure flag flip: cheap enough to run after every relevant commit.
  class Invalidate
    def self.call(user_id:)
      return if user_id.blank?

      ReconciliationState.where(user_id: user_id).where.not(stale: true).update_all(stale: true) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end

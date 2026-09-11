# frozen_string_literal: true

# One row per routed AI resolution step: a cache hit, a deterministic
# resolution, or a cheap/strong model attempt. Powers the Ai::Metrics usage
# and fallback reporting.
class AiRequest < ApplicationRecord
  STRATEGIES = %w[deterministic cache cheap_ai strong_ai].freeze
  STATUSES = %w[ok low_confidence error].freeze

  belongs_to :user, optional: true

  validates :task, presence: true
  validates :strategy, presence: true, inclusion: { in: STRATEGIES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :ai_calls, -> { where(strategy: %w[cheap_ai strong_ai]) }
  scope :cache_hits, -> { where(strategy: "cache") }
end

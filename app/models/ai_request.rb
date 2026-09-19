# frozen_string_literal: true

# One row per routed AI resolution step: a cache hit, a deterministic
# resolution, or a cheap/strong model attempt. Powers the Ai::Metrics usage
# and fallback reporting.
class AiRequest < ApplicationRecord
  STRATEGIES = %w[deterministic cache cheap_ai strong_ai override].freeze
  STATUSES = %w[ok low_confidence error].freeze

  belongs_to :user, optional: true

  validates :task, presence: true
  validates :strategy, presence: true, inclusion: { in: STRATEGIES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :ai_calls, -> { where(strategy: %w[cheap_ai strong_ai]) }
  scope :cache_hits, -> { where(strategy: "cache") }

  # Throughput of this single call; nil when tokens or latency are missing.
  def tokens_per_second
    return nil if output_tokens.to_i <= 0 || latency_ms.to_i <= 0

    (output_tokens / (latency_ms / 1000.0)).round(2)
  end
end

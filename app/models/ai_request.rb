# frozen_string_literal: true

# One row per routed AI resolution step: a cache hit, a deterministic
# resolution, or a cheap/strong model attempt. Powers the Ai::Metrics usage
# and fallback reporting.
class AiRequest < ApplicationRecord
  STRATEGIES = %w[deterministic cache cheap_ai strong_ai override].freeze
  STATUSES = %w[ok low_confidence error].freeze

  belongs_to :user, optional: true

  include EncryptedSecret
  # Telemetry rows carry full conversation content: encrypted at rest with
  # the app secret, same scheme as the OAuth tokens. The prompt keeps its
  # array-of-messages shape through a JSON roundtrip (jsonb typing).
  encrypts_secret :output

  def prompt
    raw = decrypt_secret(self[:prompt])
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    raw
  end

  def prompt=(value)
    self[:prompt] = value.nil? ? nil : encrypt_secret(JSON.generate(value))
  end

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

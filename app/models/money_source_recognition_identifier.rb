# frozen_string_literal: true

# MoneySourceRecognitionIdentifier
# A single recognition signal for a Money Source: a keyword (matched against
# email body), a sender/domain (matched against the From header) or a
# subject/header pattern. Each identifier has a type, a normalized value and
# a lifecycle state:
#   status: "confirmed" (user accepted — used for matching) or "suggested"
#           (discovered by e.g. Gmail sync — shown for review, NEVER used
#           for matching and never silently promoted).
#   origin: "user" (typed/accepted on the recognition page) or "gmail"
#           (discovered during a sync).
class MoneySourceRecognitionIdentifier < ApplicationRecord
  KINDS = %w[keyword sender domain subject header].freeze
  STATUSES = %w[confirmed suggested].freeze
  ORIGINS = %w[user gmail].freeze

  # autosave so identifiers can be created on a lazily built (unsaved)
  # recognition record — the parent is persisted first automatically.
  belongs_to :money_source_recognition, autosave: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :origin, presence: true, inclusion: { in: ORIGINS }
  validates :value, presence: true
  validates :value, uniqueness: { scope: %i[money_source_recognition_id kind] }
  validates :observation_count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  before_validation :normalize_value
  before_validation :set_defaults

  scope :confirmed, -> { where(status: "confirmed") }
  scope :suggested, -> { where(status: "suggested") }

  def keyword? = kind == "keyword"
  def sender? = kind == "sender"
  def domain? = kind == "domain"
  def subject? = kind == "subject"
  def header? = kind == "header"

  def confirmed? = status == "confirmed"
  def suggested? = status == "suggested"

  # Domain-based uniqueness: a domain and a full address are both "sender"
  # signals. We normalize lowercase and strip, but keep the value as typed so
  # the UI can show the original.
  def self.normalize(value)
    value.to_s.strip
  end

  private

  def set_defaults
    self.status ||= "confirmed"
    self.origin ||= "user"
    self.observation_count ||= 1
  end

  def normalize_value
    self.value = self.class.normalize(value)
  end
end

# frozen_string_literal: true

# MoneySourceRecognitionIdentifier
# A single recognition signal for a Money Source: a keyword (matched against
# email body), a sender/domain (matched against the From header) or a
# subject/header pattern. Each identifier has a type and a normalized value.
class MoneySourceRecognitionIdentifier < ApplicationRecord
  KINDS = %w[keyword sender domain subject header].freeze

  belongs_to :money_source_recognition

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :value, presence: true
  validates :value, uniqueness: { scope: %i[money_source_recognition_id kind] }

  before_validation :normalize_value

  def keyword? = kind == "keyword"
  def sender? = kind == "sender"
  def domain? = kind == "domain"
  def subject? = kind == "subject"
  def header? = kind == "header"

  # Domain-based uniqueness: a domain and a full address are both "sender"
  # signals. We normalize lowecase and strip, but keep the value as typed so
  # the UI can show the original.
  def self.normalize(value)
    value.to_s.strip
  end

  private

  def normalize_value
    self.value = self.class.normalize(value)
  end
end

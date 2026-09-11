# frozen_string_literal: true

# SpreadsheetFormatMapping
# Remembers the column layout of a previously seen spreadsheet format so
# later imports with the same structure skip AI completely. The fingerprint
# is a hash of the normalized header row, so equivalent exports from the
# same bank reuse one mapping.
#
# Example:
#   mapping = SpreadsheetFormatMapping.lookup(user: user, headers: ["Fecha", "Descripción", "Débito"])
#   # => nil on first sight; after the AI maps it once:
#   mapping.mapping # => { "date_column" => "Fecha", "description_column" => "Descripción", ... }
class SpreadsheetFormatMapping < ApplicationRecord
  SOURCES = %w[user rule cheap_ai strong_ai ai].freeze

  belongs_to :user

  validates :fingerprint, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :fingerprint, uniqueness: { scope: :user_id }

  scope :for_user, ->(user) { where(user_id: user.id) }

  def self.fingerprint(headers)
    normalized = Array(headers).map { |h| normalize_header(h) }.reject(&:blank?)
    Digest::SHA256.hexdigest(normalized.join("|"))
  end

  def self.lookup(user:, headers:)
    for_user(user).find_by(fingerprint: fingerprint(headers))
  end

  def self.record!(user:, headers:, mapping:, source:, bank: nil, confidence: nil)
    return nil if mapping.blank?

    source = source.to_s
    source = "ai" unless SOURCES.include?(source)

    record = for_user(user).find_or_initialize_by(fingerprint: fingerprint(headers))
    # A stored user/rule mapping always wins over a fresh AI suggestion.
    if record.persisted? && %w[user rule].include?(record.source) && !%w[user rule].include?(source)
      return record
    end

    record.assign_attributes(headers: Array(headers).map(&:to_s), mapping: mapping,
                             source: source, bank: bank, confidence: confidence)
    record.save!
    record
  end

  def self.normalize_header(header)
    header.to_s.downcase.tr("áéíóúü", "aeiouu").gsub(/\s+/, " ").strip
  end
end

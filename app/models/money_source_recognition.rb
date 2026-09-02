# frozen_string_literal: true

# MoneySourceRecognition
# Holds the recognition configuration for a single Money Source. Optional
# (absent == "Sin configurar"). The actual matching signals live in
# MoneySourceRecognitionIdentifier (typed: keyword / sender / domain /
# subject / header).
class MoneySourceRecognition < ApplicationRecord
  belongs_to :money_source
  has_many :recognition_identifiers, class_name: "MoneySourceRecognitionIdentifier",
                                     dependent: :destroy, inverse_of: :money_source_recognition

  validates :money_source, presence: true

  # Full replace of the identifiers for the given kinds. Values are normalized
  # before saving. When the recognition record is new it is persisted first so
  # children can reference it. Returns true when configured (≥ 1 id still set).
  def replace_identifiers(**values_by_kind)
    transaction do
      save! if new_record?

      values_by_kind.each do |kind, values|
        kind_str = kind.to_s
        next unless MoneySourceRecognitionIdentifier::KINDS.include?(kind_str)

        wanted = Array(values).compact_blank.map { |v| MoneySourceRecognitionIdentifier.normalize(v) }
        existing = recognition_identifiers.where(kind: kind_str).index_by(&:value)
        wanted.uniq.each_with_index do |value, index|
          id = existing.delete(value)
          record = id || recognition_identifiers.build(kind: kind_str)
          record.value = value
          record.position = index
          record.save!
        end
        existing.each_value(&:destroy!)
      end

      # Re-sync the in-memory association so callers (and reloads of the same
      # object) always read the values just written.
      recognition_identifiers.reload
    end
    configured?
  end

  def configured?
    recognition_identifiers.any?
  end
end

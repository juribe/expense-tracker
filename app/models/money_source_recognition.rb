# frozen_string_literal: true

# MoneySourceRecognition
# Holds the recognition configuration for a single Money Source. Optional
# (absent == "Sin configurar"). The actual matching signals live in
# MoneySourceRecognitionIdentifier (typed: keyword / sender / domain /
# subject / header; status: confirmed / suggested).
class MoneySourceRecognition < ApplicationRecord
  belongs_to :money_source
  has_many :recognition_identifiers, class_name: "MoneySourceRecognitionIdentifier",
                                     dependent: :destroy, inverse_of: :money_source_recognition

  validates :money_source, presence: true

  # Full replace of the CONFIRMED identifiers for the given kinds. Values are
  # normalized before saving. Persisted suggested identifiers are preserved:
  # a value submitted by the form promotes its suggested row to confirmed
  # (the user explicitly accepted it); suggested rows the form does not
  # mention stay untouched as suggestions. Returns true when configured
  # (≥ 1 confirmed identifier still set).
  def replace_identifiers(**values_by_kind)
    transaction do
      save! if new_record?

      values_by_kind.each do |kind, values|
        kind_str = kind.to_s
        next unless MoneySourceRecognitionIdentifier::KINDS.include?(kind_str)

        wanted = Array(values).compact_blank.map { |v| MoneySourceRecognitionIdentifier.normalize(v) }
        existing = recognition_identifiers.where(kind: kind_str).index_by(&:value)
        wanted.uniq.each_with_index do |value, index|
          record = existing.delete(value)
          if record.nil?
            record = recognition_identifiers.build(kind: kind_str)
          elsif record.suggested?
            # The user accepted a suggestion: promote it, never duplicate it.
            record.assign_attributes(status: "confirmed", origin: "user")
          end
          record.value = value
          record.position = index
          record.save!
        end
        existing.each_value { |record| record.destroy! if record.confirmed? }
      end

      # Re-sync the in-memory association so callers (and reloads of the same
      # object) always read the values just written.
      recognition_identifiers.reload
    end
    configured?
  end

  # Deletes persisted suggestions (by section kind group and values) that the
  # user explicitly dismissed on the recognition page. Confirmed values are
  # never touched.
  def dismiss_suggestions!(dismissed_by_section)
    dismissed_by_section.each do |section, values|
      kinds = self.class.section_kinds(section.to_s)
      next if kinds.empty?

      wanted = Array(values).compact_blank.map { |v| MoneySourceRecognitionIdentifier.normalize(v) }
      next if wanted.empty?

      recognition_identifiers.suggested.where(kind: kinds, value: wanted).destroy_all
    end
    recognition_identifiers.reload
  end

  def configured?
    recognition_identifiers.confirmed.any?
  end

  # Maps a UI chip section (keywords / senders / subjects) to the identifier
  # kinds it may contain.
  def self.section_kinds(section)
    {
      "keywords" => %w[keyword],
      "senders" => %w[sender domain],
      "subjects" => %w[subject header]
    }.fetch(section, [])
  end
end

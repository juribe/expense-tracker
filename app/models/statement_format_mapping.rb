# frozen_string_literal: true

# StatementFormatMapping
# Remembers the learned layout of a previously seen bank statement so later
# statements of the same format are parsed deterministically without AI. A
# recipe belongs to the money source (card/loan) it was learned from, so the
# first upload of a statement teaches the layout and every later upload of that
# same source reuses it. The layout is recognised by its anchor lines (stable
# headings/substrings), not by a content hash, so statements with different
# transactions but the same structure reuse one mapping.
#
# Example:
#   mapping = StatementFormatMapping.lookup(user: user, text: text, money_source: card)
#   # => nil on first sight; after the AI describes the layout once:
#   mapping.row_spec # => { "fields" => [ { "token" => "date" }, ... ] }
class StatementFormatMapping < ApplicationRecord
  SOURCES = %w[ai user].freeze

  # Bumping this ignores every recipe produced by an older prompt so it is
  # re-learned on the next upload (e.g. when the summary selectors changed).
  CURRENT_RECIPE_VERSION = 1

  belongs_to :user
  belongs_to :money_source

  validates :source, inclusion: { in: SOURCES }

  scope :for_user, ->(user) { where(user: user) }
  scope :for_source, ->(money_source) { where(money_source: money_source) }
  scope :current_recipe, -> { where(recipe_version: CURRENT_RECIPE_VERSION) }

  # The fingerprint is only used for uniqueness/dedup (the layout lookup is
  # anchor-based, not hash-based), so it hashes the normalized anchor set.
  def self.fingerprint(anchors)
    normalized = Array(anchors).map { |anchor| normalize_anchor(anchor) }.reject(&:blank?)
    Digest::SHA256.hexdigest(normalized.join("|"))
  end

  # Anchor-based lookup within one money source: the first mapping whose every
  # anchor line appears in the text wins; when several match, the most specific
  # (most anchors) is chosen. Only recipes written by the current recipe version
  # are eligible. There is no cross-source fallback: a card's recipe never
  # parses another card's statement.
  def self.lookup(user:, text:, money_source:)
    return nil if money_source.nil?

    current_recipe.for_user(user).for_source(money_source)
                  .select { |mapping| mapping.matches_text?(text) }
                  .max_by { |mapping| Array(mapping.anchors).size }
  end

  # Persists (or refreshes) the layout recipe the AI described for one money
  # source. Idempotent per (source, anchors): re-learning the same format
  # updates the existing row instead of creating a duplicate.
  def self.record!(user:, money_source:, anchors:, sections:, row:, bank: nil,
                   confidence: nil, source: "ai", summary: {}, recipe_version: nil)
    anchors = Array(anchors).map(&:to_s)
    return nil if anchors.blank? || money_source.nil?

    source = source.to_s
    source = "ai" unless SOURCES.include?(source)

    record = for_user(user).for_source(money_source).find_or_initialize_by(fingerprint: fingerprint(anchors))
    record.assign_attributes(
      anchors: anchors, bank: bank, sections: sections || {}, row_spec: row || {},
      summary_spec: summary || {}, recipe_version: recipe_version || CURRENT_RECIPE_VERSION,
      source: source, confidence: confidence
    )
    record.save!
    record
  end

  def self.normalize_anchor(anchor)
    anchor.to_s.downcase.gsub(/\s+/, " ").strip
  end

  def matches_text?(text)
    anchors.present? && Array(anchors).all? { |anchor| text.to_s.include?(anchor) }
  end
end

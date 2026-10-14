# frozen_string_literal: true

# StatementFormatMapping
# Remembers the learned layout of a previously seen bank statement so later
# statements of the same format are parsed deterministically without AI. The
# layout is recognised by its anchor lines (stable headings/substrings), not
# by a content hash, so statements with different transactions but the same
# structure reuse one mapping.
#
# Example:
#   mapping = StatementFormatMapping.lookup(user: user, text: statement_text)
#   # => nil on first sight; after the AI describes the layout once:
#   mapping.row_spec # => { "fields" => [ { "token" => "date" }, ... ] }
class StatementFormatMapping < ApplicationRecord
  SOURCES = %w[user rule ai].freeze

  # Bumped whenever the AI layout recipe changes shape (e.g. when summary
  # selectors were added). Mappings stored by an older recipe are ignored by
  # lookups so the next upload re-learns with the current recipe.
  CURRENT_RECIPE_VERSION = 1

  belongs_to :user

  validates :fingerprint, presence: true, uniqueness: { scope: :user_id }
  validates :source, presence: true, inclusion: { in: SOURCES }

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :current_recipe, -> { where(recipe_version: CURRENT_RECIPE_VERSION) }

  # The fingerprint is only used for uniqueness/dedup (the layout lookup is
  # anchor-based, not hash-based), so it hashes the normalized anchor set.
  def self.fingerprint(anchors)
    normalized = Array(anchors).map { |anchor| normalize_anchor(anchor) }.reject(&:blank?)
    Digest::SHA256.hexdigest(normalized.join("|"))
  end

  # Anchor-based lookup: the first mapping of the user whose every anchor
  # line appears in the text wins; when several match, the most specific one
  # (the mapping with the most anchors) is chosen. Only recipes written by the
  # current recipe version are eligible; older ones are ignored and re-learned.
  def self.lookup(user:, text:)
    current_recipe.for_user(user).select { |mapping| mapping.matches_text?(text) }
                                .max_by { |mapping| Array(mapping.anchors).size }
  end

  def self.record!(user:, anchors:, sections:, row:, bank: nil, confidence: nil,
                   source: "ai", skip_income: true, summary: {}, recipe_version: nil)
    return nil if Array(anchors).blank?

    source = source.to_s
    source = "ai" unless SOURCES.include?(source)

    record = for_user(user).find_or_initialize_by(fingerprint: fingerprint(anchors))
    record.assign_attributes(
      anchors: Array(anchors).map(&:to_s), bank: bank,
      sections: sections || {}, row_spec: row || {},
      summary_spec: summary || {}, recipe_version: recipe_version || CURRENT_RECIPE_VERSION,
      skip_income: skip_income, source: source, confidence: confidence
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

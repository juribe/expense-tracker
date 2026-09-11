# frozen_string_literal: true

# ActivityClassification
# Reusable classification knowledge for a merchant/activity name: maps a
# normalized activity (e.g. "didi food") to a category so future imports reuse
# the same classification without a new AI request.
#
# Source precedence: user → ai → rule. A user correction always overrides
# previous AI/rule knowledge. One row per (user, normalized_name).
#
# Example: ActivityClassification.record!(user: user, name: "DIDI FOOD", category: food, source: "ai")
class ActivityClassification < ApplicationRecord
  # "cheap_ai"/"strong_ai" identify which model tier produced the knowledge;
  # "ai" is kept for records created before tiers existed.
  SOURCES = %w[ai cheap_ai strong_ai user rule].freeze
  PRECEDENCE = { "user" => 0, "cheap_ai" => 1, "strong_ai" => 1, "ai" => 1, "rule" => 2 }.freeze

  belongs_to :user
  belongs_to :category, optional: true

  validates :normalized_name, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :normalized_name, uniqueness: { scope: :user_id }
  validates :category_id, presence: true

  scope :for_user, ->(user) { where(user_id: user.id) }

  def self.normalize_name(text)
    return nil if text.blank?

    name = ActiveSupport::Inflector.transliterate(text.to_s).downcase.strip
    # Drop merchant-reference suffixes such as "DIDI FOOD *12345" or
    # "Netflix-99123" so equivalent names reuse the same classification.
    name = name.gsub(/(?:[·\-*#]\s*\p{N}+\s*)$/, "")
    name.gsub(/[^\p{L}\p{N}\s]/, " ").squish.presence&.truncate(255)
  end

  # Stores or refreshes the classification for a (user, activity). A user
  # correction overrides any prior knowledge; AI/rule suggestions never
  # overwrite a user correction. Returns the stored record or nil.
  def self.record!(user:, name:, category:, source:)
    normalized = normalize_name(name)
    return nil if normalized.blank? || category.blank?

    source = source.to_s
    return nil unless SOURCES.include?(source)

    category = category_for(user, category)
    return nil if category.nil?

    existing = for_user(user).find_by(normalized_name: normalized)

    if existing
      return existing if existing.user_override? && source != "user"

      existing.update!(category: category, source: source, original_name: name)
      existing
    else
      create!(user: user, normalized_name: normalized, original_name: name, category: category, source: source)
    end
  end

  # Strongest stored classification for an activity, or nil.
  def self.lookup(user:, name:)
    normalized = normalize_name(name)
    return nil if normalized.blank?

    for_user(user).where(normalized_name: normalized)
                  .order(Arel.sql("CASE source WHEN 'user' THEN 0 WHEN 'rule' THEN 2 ELSE 1 END"))
                  .first
  end

  def user_override?
    source == "user"
  end

  def self.category_for(user, category)
    case category
    when Category then category
    when nil then nil
    else Category.for_user(user).find_by("lower(name) = ?", category.to_s.downcase)
    end
  end
  private_class_method :category_for
end

# frozen_string_literal: true

# TransactionRule
# A user-authored automatic rule that categorizes/organizes transactions when
# they are created or imported.
#
# Associations: belongs_to :user (required), category & money sources (optional)
# Methods: matches?(transaction), condition_label, action_label, title
#
# Example: TransactionRule.active.for_user(user)
class TransactionRule < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :money_source_condition, class_name: "MoneySource", optional: true
  belongs_to :action_money_source, class_name: "MoneySource", optional: true

  validates :enabled, inclusion: { in: [ true, false ] }
  validates :priority, numericality: { only_integer: true, allow_nil: true }
  validate :at_least_one_condition
  validate :at_least_one_action
  validate :condition_and_action_values_valid

  scope :active, -> { where(enabled: true) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  # Deterministic precedence: amount-specific rules first, then money-source +
  # merchant combos, then merchant rules, then generic description rules.
  # Within a tier the highest priority (then most recently updated) wins.
  scope :ordered_by_specificity, lambda {
    order(Arel.sql(
      "CASE
        WHEN amount_gt IS NOT NULL OR amount_lt IS NOT NULL THEN 0
        WHEN money_source_condition_id IS NOT NULL AND merchant_contains IS NOT NULL THEN 1
        WHEN merchant_contains IS NOT NULL THEN 2
        WHEN money_source_condition_id IS NOT NULL THEN 3
        ELSE 4
      END, priority DESC, updated_at DESC"
    ))
  }

  def title
    name.presence || merchant_contains.presence || description_contains.presence || "Rule"
  end

  def matches?(transaction)
    return false unless enabled?

    merchant_matches?(transaction) &&
      description_matches?(transaction) &&
      money_source_matches?(transaction) &&
      amount_matches?(transaction)
  end

  def apply_to(transaction)
    return if transaction.nil?
    return if transaction.applied_rule_ids.include?(id)

    changed = false

    if category_id.present? && transaction.category_id.blank?
      transaction.category_id = category_id
      transaction.rule_id = id
      changed = true
    end

    if action_money_source_id.present? && transaction.money_source_id.blank?
      transaction.money_source_id = action_money_source_id
      changed = true
    end

    if tag.present? && !transaction_has_tag?(transaction)
      transaction.add_tag(tag)
      changed = true
    end

    if changed
      transaction.applied_rule_ids = (transaction.applied_rule_ids || []) | [ id ]
    end

    transaction
  end

  private

  def merchant_matches?(transaction)
    return true if merchant_contains.blank?

    transaction.description.to_s.downcase.include?(merchant_contains.downcase)
  end

  def description_matches?(transaction)
    return true if description_contains.blank?

    transaction.description.to_s.downcase.include?(description_contains.downcase)
  end

  def money_source_matches?(transaction)
    return true if money_source_condition_id.blank?

    transaction.money_source_id == money_source_condition_id
  end

  def amount_matches?(transaction)
    abs = transaction.amount.to_d.abs
    return false if amount_gt.present? && abs <= amount_gt.to_d
    return false if amount_lt.present? && abs >= amount_lt.to_d

    true
  end

  def transaction_has_tag?(transaction)
    transaction.tags.include?(tag)
  end

  def at_least_one_condition
    if merchant_contains.blank? && description_contains.blank? &&
       money_source_condition_id.blank? && amount_gt.blank? && amount_lt.blank?
      errors.add(:base, I18n.t("transaction_rules.validation.at_least_one_condition"))
    end
  end

  def at_least_one_action
    if category_id.blank? && tag.blank? && action_money_source_id.blank?
      errors.add(:base, I18n.t("transaction_rules.validation.at_least_one_action"))
    end
  end

  def condition_and_action_values_valid
    errors.add(:merchant_contains, "can't be blank") if merchant_contains.present? && merchant_contains.strip.blank?
    errors.add(:description_contains, "can't be blank") if description_contains.present? && description_contains.strip.blank?
  end
end

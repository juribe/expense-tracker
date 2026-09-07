# frozen_string_literal: true

# TransactionRulesHelper
# Methods: condition_options, action_options, selected_condition_field,
#   selected_action_field
#
# Example: condition_options # => [["Merchant contains", "merchant_contains"], ...]
module TransactionRulesHelper
  def condition_options
    [
      [ t("transaction_rules.merchant_contains"), "merchant_contains" ],
      [ t("transaction_rules.description_contains"), "description_contains" ],
      [ t("transaction_rules.money_source_is"), "money_source_condition" ],
      [ t("transaction_rules.amount_greater_than"), "amount_gt" ],
      [ t("transaction_rules.amount_less_than"), "amount_lt" ]
    ]
  end

  def action_options
    [
      [ t("transaction_rules.action_category"), "category" ],
      [ t("transaction_rules.action_tag"), "tag" ],
      [ t("transaction_rules.action_money_source"), "money_source" ]
    ]
  end

  def selected_condition_field(rule)
    if rule.merchant_contains.present? then "merchant_contains"
    elsif rule.description_contains.present? then "description_contains"
    elsif rule.money_source_condition_id.present? then "money_source_condition"
    elsif rule.amount_gt.present? then "amount_gt"
    elsif rule.amount_lt.present? then "amount_lt"
    else "merchant_contains"
    end
  end

  def selected_action_field(rule)
    if rule.category_id.present? then "category"
    elsif rule.tag.present? then "tag"
    elsif rule.action_money_source_id.present? then "money_source"
    else "category"
    end
  end

  # Localized, human-readable condition description for a rule card.
  def rule_condition_text(rule)
    return t("transaction_rules.merchant_contains") if rule.merchant_contains.present?
    return t("transaction_rules.description_contains") if rule.description_contains.present?
    return t("transaction_rules.money_source_is") if rule.money_source_condition_id.present?
    return t("transaction_rules.amount_greater_than") if rule.amount_gt.present?
    return t("transaction_rules.amount_less_than") if rule.amount_lt.present?

    ""
  end

  def rule_condition_value(rule)
    if rule.merchant_contains.present? then rule.merchant_contains
    elsif rule.description_contains.present? then rule.description_contains
    elsif rule.money_source_condition_id.present? then rule.money_source_condition.display_name
    elsif rule.amount_gt.present? then number_to_currency(rule.amount_gt)
    elsif rule.amount_lt.present? then number_to_currency(rule.amount_lt)
    else ""
    end
  end

  # Localized action lines for a rule card, e.g. ["Category → Fitness"].
  def rule_action_lines(rule)
    lines = []
    lines << "#{t("transaction_rules.action_category")} → #{rule.category.name}" if rule.category_id.present?
    lines << "#{t("transaction_rules.action_tag")} → #{rule.tag}" if rule.tag.present?
    lines << "#{t("transaction_rules.action_money_source")} → #{rule.action_money_source.display_name}" if rule.action_money_source_id.present?
    lines
  end
end
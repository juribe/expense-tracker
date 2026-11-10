# frozen_string_literal: true

# TransactionRulesHelper
# Methods: condition_options, action_options, selected_condition_field,
#   selected_action_field, rule_condition_text, rule_condition_value,
#   rule_condition_icon, rule_actions, rule_search_terms, suggestion_reason
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

  # Why the suggestion exists: repeated corrections or a dominant category
  # across recent transactions. Count is pluralized through I18n.
  def suggestion_reason(suggestion)
    key = suggestion[:kind] == :correction ? "suggestions_based_on_corrections" : "suggestions_based_on_transactions"
    t("transaction_rules.#{key}", count: suggestion[:count])
  end

  # Icon that matches the rule's active condition.
  def rule_condition_icon(rule)
    return "ti-building-store" if rule.merchant_contains.present?
    return "ti-text-size" if rule.description_contains.present?
    return "ti-wallet" if rule.money_source_condition_id.present?
    return "ti-coin" if rule.amount_gt.present? || rule.amount_lt.present?

    "ti-filter"
  end

  # Structured action rows for the redesigned rule card. Each row carries the
  # localized label, the value and the icon that identifies the action type.
  def rule_actions(rule)
    actions = []

    if rule.category.present?
      actions << {
        label: t("transaction_rules.result_category"),
        value: rule.category.name,
        icon: category_icon_klass(rule.category)
      }
    end

    if rule.tag.present?
      actions << {
        label: t("transaction_rules.result_tag"),
        value: rule.tag,
        icon: "ti ti-hash"
      }
    end

    action_money_source = rule.action_money_source if rule.action_money_source_id.present?

    if action_money_source
      actions << {
        label: t("transaction_rules.result_money_source"),
        value: action_money_source.display_name,
        icon: "ti ti-#{source_kind_icon(action_money_source.kind)}"
      }
    end

    actions
  end

  # Text used by the client-side search: rule name, condition and every action
  # value. Keeps the search independent from the rendered markup.
  def rule_search_terms(rule)
    values = [ rule.title, rule_condition_text(rule), rule_condition_value(rule) ]
    values.concat(rule_actions(rule).map { |action| action[:value] })
    values.join(" ")
  end
end

# frozen_string_literal: true

# SavingsOpportunitiesHelper
# Presentation helpers for the savings opportunities page. Financial values
# arrive computed from the backend; these methods only format and label them.
#
# Methods: savings_money, savings_percentage, savings_delta_badge,
#          savings_bar_height, savings_frequency_label, savings_confidence_badge,
#          savings_updated_label, savings_highlight, savings_quick_percentage
#
# Example: savings_delta_badge(30.8) # => <span class="so-trend">↑ +30,8%</span>
module SavingsOpportunitiesHelper
  QUICK_PERCENTAGES = [ 5, 10, 15, 20 ].freeze

  def savings_money(value)
    number_to_currency(value.to_d, precision: 0)
  end

  def savings_percentage(value)
    return "—" if value.nil?

    "#{number_with_precision(value.to_f, precision: 1, separator: ",")}%"
  end

  def savings_delta_badge(delta_pct)
    if delta_pct.nil?
      return content_tag(:span, t("savings_opportunities.categories.new_label"),
                         class: "so-trend so-trend-neutral")
    end

    up = delta_pct >= 0
    icon = up ? "ti-arrow-up-right" : "ti-arrow-down-right"
    content_tag(:span, class: "so-trend #{up ? 'so-trend-up' : 'so-trend-down'}") do
      content_tag(:i, "", class: "ti #{icon} me-1") + "#{up ? '+' : '−'}#{savings_percentage(delta_pct.abs)}"
    end
  end

  def savings_bar_height(total, max, max_height: 112)
    return 0 if total.to_d <= 0 || max.to_d <= 0

    height = (total.to_d / max.to_d * max_height).round
    height.clamp(8, max_height)
  end

  def savings_frequency_label(frequency)
    t("savings_opportunities.frequencies.#{frequency}", default: frequency.to_s)
  end

  def savings_confidence_badge(confidence)
    label, tone =
      case confidence.to_sym
      when :confirmed
        [ t("savings_opportunities.recurring.confirmed"), "so-badge-confirmed" ]
      when :configured
        [ t("savings_opportunities.recurring.configured"), "so-badge-review" ]
      else
        [ t("savings_opportunities.recurring.possible"), "so-badge-review" ]
      end

    content_tag(:span, label, class: "so-badge #{tone}")
  end

  def savings_updated_label(timestamp)
    return t("savings_opportunities.ai.not_generated") if timestamp.blank?

    time = Time.zone.parse(timestamp.to_s)
    return t("savings_opportunities.ai.updated_today") if time.to_date == Date.current

    t("savings_opportunities.ai.updated_on", date: I18n.l(time.to_date))
  rescue ArgumentError, TypeError
    t("savings_opportunities.ai.not_generated")
  end

  def savings_highlight(narrative, reference)
    (narrative["highlights"] || {}).fetch(reference, {})
  end

  def savings_quick_percentage(row)
    suggested = row[:suggested_percentage].to_i
    QUICK_PERCENTAGES.include?(suggested) ? suggested : 10
  end

  def savings_initial(name)
    name.to_s.strip.first&.upcase || "•"
  end

  def savings_weekday_name(index)
    return nil if index.nil?

    t("date.day_names")[index.to_i]
  end
end

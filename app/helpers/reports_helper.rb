# frozen_string_literal: true

# ReportsHelper
# Presentation helpers for the Reports section.
#
# Methods: money_amount, delta_badge, progress_usage
#
# Example: delta_badge(delta_pct, good_when_positive: false) # => "↑ 12.4% vs periodo anterior"
module ReportsHelper
  def money_amount(value)
    return content_tag(:span, "—", class: "text-muted") if value.blank?

    number_to_currency(value.to_d, precision: 0)
  end

  def delta_badge(delta_pct, good_when_positive: false)
    return content_tag(:span, "—", class: "text-muted") if delta_pct.blank?

    up = delta_pct >= 0
    color = up == good_when_positive ? "text-success" : "text-danger"
    icon = up ? "ti-arrow-up-right" : "ti-arrow-down-right"
    content_tag(:span, class: "#{color} small") do
      content_tag(:i, "", class: "ti #{icon} me-1") + "#{number_with_delimiter(delta_pct.abs, precision: 1)}% " +
        t("reports.period.vs_previous")
    end
  end

  # Table variant of the change label: green/red arrow with the percentage,
  # em dash when there is no comparable previous data.
  def category_delta_label(delta_pct)
    return content_tag(:span, "—", class: "text-muted") if delta_pct.blank?

    up = delta_pct >= 0
    color = up ? "text-success" : "text-danger"
    icon = up ? "ti-arrow-up-right" : "ti-arrow-down-right"
    content_tag(:span, class: "#{color} small text-nowrap") do
      content_tag(:i, "", class: "ti #{icon} me-1") +
        "#{number_with_delimiter(delta_pct.abs, precision: 1)}% #{t('reports.period.vs_previous')}"
    end
  end

  def usage_progress(pct_used)
    pct = [ [ pct_used.to_f, 0 ].max, 100 ].min
    variant = pct_used.to_f > 100 ? "danger" : (pct_used.to_f >= Budget::NEAR_LIMIT_PERCENT ? "warning" : "success")
    content_tag(:div, class: "progress", style: "height: 8px;") do
      content_tag(:div, "", class: "progress-bar bg-#{variant}",
                        style: "width: #{pct}%;",
                        role: "progressbar", "aria-valuenow": pct_used, "aria-valuemin": 0, "aria-valuemax": 100)
    end
  end

  def period_presets(user: nil)
    user ||= current_user if respond_to?(:current_user)
    presets = Reports::Period.cycles_enabled?(user) ? Reports::Period::CYCLE_PRESETS : Reports::Period::PRESETS

    presets.map do |preset|
      [ period_preset_label(preset, user), preset ]
    end
  end

  # The two single-cycle presets name their concrete range ("Este ciclo
  # (Oct 20 – Nov 4)") so the selector is unambiguous about which months it
  # covers; multi-cycle and calendar presets keep their static labels.
  def period_preset_label(preset, user)
    base = t("reports.period.presets.#{preset}")
    return base unless user.present? && %w[this_cycle last_cycle].include?(preset)

    cycle = preset == "this_cycle" ? PayCycle.current(user) : PayCycle.previous(user)
    "#{base} (#{cycle.label})"
  end

  def category_options
    @category_options ||= current_user.present? ? Category.for_user_and_type(current_user, "expense").pluck(:name, :id) : []
  end

  def money_source_options
    @money_source_options ||= current_user.present? ? current_user.money_sources.active.order(:kind, :name).map { |s| [ s.name, s.id ] } : []
  end

  def credit_card_options
    @credit_card_options ||= current_user.present? ? current_user.money_sources.active.by_kind("credit_card").map { |s| [ s.name, s.id ] } : []
  end

  def loan_options
    @loan_options ||= current_user.present? ? current_user.money_sources.active.by_kind("loan").map { |s| [ s.name, s.id ] } : []
  end

  def kind_options
    [
      [ t("types.expense"), "expense" ],
      [ t("types.income"), "income" ]
    ]
  end

  # Chart.js renders to canvas and cannot resolve CSS var() colors, so the
  # chart palette is hardcoded as hex values here.
  CHART_COLORS = %w[
    #7FA7D8 #9B8BC4 #D48FA8 #D99A72 #D8B45C #75B89B #70B8C5
    #8299C7 #8EAF8B #B08FC2 #C8877D #7FAFA8 #B59A7A #8D9BB8 #C19A6B
  ].freeze

  def category_colors(rows)
    rows.each_with_index.map { |_row, index| CHART_COLORS[index % CHART_COLORS.size] }
  end

  def filter_params_for(**overrides)
    base = params.to_unsafe_h.slice("period", "start_date", "end_date", "category_id",
                                    "money_source_id", "credit_card_id", "loan_id", "kind")
    (base.symbolize_keys.merge(overrides)).compact_blank
  end

  def next_due_date_label(day)
    candidate = Date.new(Date.current.year, Date.current.month, day.to_i)
    candidate = candidate.next_month if candidate < Date.current
    candidate
  rescue Date::Error, ArgumentError, TypeError
    Date.current.end_of_month
  end
end

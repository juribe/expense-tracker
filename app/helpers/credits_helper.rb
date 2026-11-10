# CreditsHelper
# View-only derivation over the credit projection + the transient quick
# comparison (Credits::Comparison.quick). No business logic lives here: every
# figure already comes from the simulator, this module only chooses what to
# highlight given the goal the user picked.
#
# Methods: credit_assumption_parts, credit_quick_goals, credit_quick_strategies,
#          credit_quick_strategy_description, credit_quick_best,
#          credit_quick_selected, credit_quick_result
#
# Example: credit_quick_result(quick, "reduce_installment")[:primary][:label]
module CreditsHelper
  QUICK_GOALS = Credits::Comparison::QUICK_STRATEGIES
  REVOLVING_EXCLUDED_GOALS = %w[reduce_term].freeze
  RECURRING_GOALS = %w[reduce_term].freeze

  # Current projections store each assumption as a { "label" =>, "value" => }
  # pair; older persisted rows may still hold a plain sentence, shown as a
  # full-width value (or split at its colon when it has one).
  def credit_assumption_parts(assumption)
    return [ assumption["label"], assumption["value"] ] if assumption.is_a?(Hash)
    return assumption.split(": ", 2) if assumption.include?(": ")

    [ nil, assumption ]
  end

  # Goals offered by the savings panel. Revolving credit has no fixed term to
  # shorten, so finishing earlier is not one of its choices. A recurring extra
  # is simulated as finishing earlier, so only that goal applies in that mode.
  def credit_quick_goals(money_source, recurring: false)
    goals = money_source&.revolving? ? QUICK_GOALS - REVOLVING_EXCLUDED_GOALS : QUICK_GOALS
    recurring ? goals & RECURRING_GOALS : goals
  end

  # Quick-comparison rows limited to the goals actually offered on the panel.
  def credit_quick_strategies(quick, goals = QUICK_GOALS)
    quick.strategies.select { |strategy| goals.include?(strategy["strategy"]) }
  end

  # Strategy copy; the recurring extra adds to the payment instead of keeping it.
  def credit_quick_strategy_description(key, recurring: false)
    suffix = recurring && key == "reduce_term" ? "recurring_description" : "description"
    t("credits.quick.strategies.#{key}.#{suffix}")
  end

  # Strategy that saves the most future interest among the offered goals
  # (reduce_term / reduce_installment / prepay_installments). Selection of a
  # goal never changes the math: every strategy is always simulated.
  def credit_quick_best(quick, goals: QUICK_GOALS)
    credit_quick_strategies(quick, goals).max_by { |strategy| strategy["interest_saved"].to_d }
  end

  # The strategy row the user's goal maps to (goals use the strategy keys).
  def credit_quick_selected(quick, goal, goals: QUICK_GOALS)
    strategies = credit_quick_strategies(quick, goals)
    strategies.find { |strategy| strategy["strategy"] == goal } || strategies.first
  end

  # Goal-aware view model for the savings results. The headline always answers
  # the goal the user picked; the bigger saver (if any) is only surfaced as a
  # secondary recommendation, never replacing the chosen goal.
  def credit_quick_result(quick, goal, goals: QUICK_GOALS)
    goal = goals.include?(goal) ? goal : goals.first
    selected = credit_quick_selected(quick, goal, goals: goals)

    {
      goal: goal,
      title: t("credits.quick.result.goals.#{goal}.title"),
      intro: t("credits.quick.result.goals.#{goal}.intro"),
      tag: t("credits.quick.result.tag", goal: t("credits.simulators.strategies.#{goal}")),
      primary: credit_quick_primary(quick, goal, selected),
      interest: credit_quick_interest(selected),
      third: credit_quick_third(goal, selected),
      recommendation: credit_quick_recommendation(quick, goal, selected, goals: goals),
      alternatives: credit_quick_alternatives(quick, goal, goals: goals)
    }
  end

  private

  # First, most relevant figure for the chosen goal.
  def credit_quick_primary(quick, goal, selected)
    key = "credits.quick.result.goals.#{goal}"
    recurring = quick.mode == "recurring" && goal == "reduce_term"
    label_key = recurring ? "#{key}.recurring_primary_label" : "#{key}.primary_label"

    detail =
      if recurring
        t("#{key}.recurring_primary_detail", amount: number_to_currency(quick.amount))
      elsif goal == "reduce_installment"
        t("#{key}.primary_detail", amount: number_to_currency(quick.current["payment"].to_d - selected["payment"].to_d))
      else
        t("#{key}.primary_detail")
      end

    { label: t(label_key), value: number_to_currency(selected["payment"].to_d), detail: detail }
  end

  def credit_quick_interest(selected)
    savings = selected["interest_saved"].to_d
    {
      label: t("credits.quick.result.interest_label"),
      value: savings.positive? ? number_to_currency(savings) : t("credits.quick.result.interest_none"),
      detail: t("credits.quick.result.interest_detail"),
      tone: savings.positive? ? :positive : nil
    }
  end

  # Second supporting figure, chosen per goal (fewer installments, unchanged
  # payoff date, or months without a payment).
  def credit_quick_third(goal, selected)
    key = "credits.quick.result.goals.#{goal}"
    value =
      case goal
      when "reduce_term"
        eliminated = selected["installments_eliminated"].to_i
        eliminated.positive? ? t("credits.quick.result.installments_value", count: eliminated) : "—"
      when "prepay_installments"
        selected["months_without_payment"].to_i
      else
        t("#{key}.third_value")
      end

    { label: t("#{key}.third_label"), value: value, detail: t("#{key}.third_detail") }
  end

  # Secondary note. When another strategy saves more interest it is offered as a
  # suggestion (with the difference), without invalidating the user's choice.
  def credit_quick_recommendation(quick, goal, selected, goals: QUICK_GOALS)
    best = credit_quick_best(quick, goals: goals)
    link = t("credits.quick.result.recommendations.link")

    case goal
    when "prepay_installments"
      { text: t("credits.quick.result.recommendations.prepay_installments.text"), target_goal: nil, link: nil }
    when "reduce_term"
      { text: t("credits.quick.result.recommendations.reduce_term.text"),
        target_goal: "reduce_installment", link: link }
    else
      return nil unless best && best["strategy"] != goal &&
                        best["interest_saved"].to_d > selected["interest_saved"].to_d

      difference = best["interest_saved"].to_d - selected["interest_saved"].to_d
      { text: t("credits.quick.result.recommendations.reduce_installment.text",
                strategy: t("credits.simulators.strategies.#{best["strategy"]}"),
                difference: number_to_currency(difference)),
        target_goal: best["strategy"], link: link }
    end
  end

  # The offered strategies, marking the chosen one and the best interest saver
  # (both badges can coincide) so they can be compared at a glance.
  def credit_quick_alternatives(quick, goal, goals: QUICK_GOALS)
    best_key = credit_quick_best(quick, goals: goals)&.fetch("strategy")

    credit_quick_strategies(quick, goals).map do |strategy|
      key = strategy["strategy"]
      savings = strategy["interest_saved"].to_d

      {
        key: key,
        label: t("credits.simulators.strategies.#{key}"),
        description: credit_quick_strategy_description(key, recurring: quick.mode == "recurring"),
        savings: savings.positive? ? number_to_currency(savings) : t("credits.quick.result.interest_none"),
        chosen: key == goal,
        best: savings.positive? && key == best_key
      }
    end
  end
end

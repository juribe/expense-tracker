# frozen_string_literal: true

require "test_helper"

# CreditsHelper: pure view derivation over the transient quick comparison
# returned by Credits::Comparison.quick. No business logic here.
class CreditsHelperTest < ActionView::TestCase
  Quick = Struct.new(:current, :strategies, keyword_init: true)

  CURRENT = {
    "payment" => "1130642.0",
    "installments" => 112,
    "payoff_date" => "2036-01-01"
  }.freeze

  def strategy(key, savings:, installments:, payment:, eliminated: 0, months_without_payment: 0,
               payoff_date: "2036-01-01")
    {
      "strategy" => key,
      "interest_saved" => savings.to_s,
      "installments" => installments,
      "installments_eliminated" => eliminated,
      "payment" => payment.to_s,
      "months_without_payment" => months_without_payment,
      "payoff_date" => payoff_date
    }
  end

  # The three strategies for an amount that pays off sooner (term), lowers the
  # monthly payment (installment) or just covers future installments (prepay).
  def quick
    Quick.new(
      current: CURRENT,
      strategies: [
        strategy("reduce_term", savings: 7_030_968, installments: 104, payment: 1_130_642,
                                eliminated: 8, payoff_date: "2035-05-01"),
        strategy("reduce_installment", savings: 6_607_610, installments: 112,
                                       payment: 1_110_838),
        strategy("prepay_installments", savings: 0, installments: 112, payment: 1_130_642,
                                        months_without_payment: 6)
      ]
    )
  end

  test "credit_quick_best picks the strategy with the highest interest saved" do
    assert_equal "reduce_term", credit_quick_best(quick)["strategy"]
  end

  test "credit_quick_result prioritizes the benefits of the chosen goal" do
    result = credit_quick_result(quick, "reduce_installment")

    assert_equal "reduce_installment", result[:goal]
    assert_equal I18n.t("credits.quick.result.goals.reduce_installment.title"), result[:title]
    assert_equal I18n.t("credits.quick.result.goals.reduce_installment.primary_label"),
                 result[:primary][:label]
    assert_equal number_to_currency(1_110_838), result[:primary][:value]
    assert_includes result[:primary][:detail], number_to_currency(1_130_642 - 1_110_838)
    assert_equal number_to_currency(6_607_610), result[:interest][:value]
    assert_equal I18n.t("credits.quick.result.goals.reduce_installment.third_value"),
                 result[:third][:value]
  end

  test "credit_quick_result keeps the current installment when finishing earlier" do
    result = credit_quick_result(quick, "reduce_term")

    assert_equal I18n.t("credits.quick.result.goals.reduce_term.primary_label"), result[:primary][:label]
    assert_equal number_to_currency(1_130_642), result[:primary][:value]
    assert_equal I18n.t("credits.quick.result.goals.reduce_term.third_label"), result[:third][:label]
    assert_equal I18n.t("credits.quick.result.installments_value", count: 8), result[:third][:value]
  end

  test "credit_quick_result states prepaying covers installments without interest savings" do
    result = credit_quick_result(quick, "prepay_installments")

    assert_equal I18n.t("credits.quick.result.goals.prepay_installments.primary_label"),
                 result[:primary][:label]
    assert_equal I18n.t("credits.quick.result.interest_none"), result[:interest][:value]
    assert_equal 6, result[:third][:value]
  end

  test "credit_quick_result recommends the bigger saver but keeps the user's goal as the headline" do
    result = credit_quick_result(quick, "reduce_installment")

    assert_equal "reduce_term", result[:recommendation][:target_goal]
    assert_includes result[:recommendation][:text],
                    I18n.t("credits.simulators.strategies.reduce_term")
    assert_includes result[:recommendation][:text], number_to_currency(7_030_968 - 6_607_610)
    assert_equal I18n.t("credits.quick.result.goals.reduce_installment.primary_label"),
                 result[:primary][:label]
  end

  test "credit_quick_result suggests freeing monthly money when finishing earliest is chosen" do
    result = credit_quick_result(quick, "reduce_term")

    assert_equal "reduce_installment", result[:recommendation][:target_goal]
  end

  test "credit_quick_result only cautions about prepaying without endorsing a switch" do
    result = credit_quick_result(quick, "prepay_installments")

    assert_nil result[:recommendation][:target_goal]
    assert_equal I18n.t("credits.quick.result.recommendations.prepay_installments.text"),
                 result[:recommendation][:text]
  end

  test "credit_quick_result lists the three alternatives marking the chosen and best saver" do
    alternatives = credit_quick_result(quick, "reduce_installment")[:alternatives]

    chosen = alternatives.find { |row| row[:key] == "reduce_installment" }
    best = alternatives.find { |row| row[:key] == "reduce_term" }
    other = alternatives.find { |row| row[:key] == "prepay_installments" }

    assert chosen[:chosen]
    assert_not chosen[:best]
    assert best[:best]
    assert_not best[:chosen]
    assert_not other[:chosen]
    assert_not other[:best]
    assert_equal I18n.t("credits.quick.result.interest_none"), other[:savings]
    assert_equal I18n.t("credits.quick.strategies.reduce_term.description"), best[:description]
  end

  test "credit_quick_result keeps the best-savings badge when the user picked that goal" do
    picked = credit_quick_result(quick, "reduce_term")[:alternatives]
                                         .find { |row| row[:key] == "reduce_term" }

    assert picked[:chosen]
    assert picked[:best]
  end
end

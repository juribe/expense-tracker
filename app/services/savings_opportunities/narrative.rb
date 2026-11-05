# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::Narrative
  # Turns the deterministic analysis into readable copy. AI is only asked to
  # interpret the aggregated, already-computed results; every amount shown to
  # the user still comes from Rails. The generated narrative is cached per
  # data fingerprint so opening the page never spends tokens twice, and any AI
  # failure falls back to the deterministic text.
  #
  # Methods: fetch, generate!, deterministic, self.ai_available?
  #
  # Example: SavingsOpportunities::Narrative.new(user:, analysis:).generate!
  class Narrative
    # Bump when the deterministic analysis shape changes so old narratives
    # cannot reference highlights that no longer exist.
    CACHE_VERSION = 2
    CACHE_TTL = 12.hours
    MAX_SUMMARY = 1200
    MAX_TEXT = 600

    attr_reader :user, :analysis, :cache, :router

    def self.ai_available?
      Ai::Providers.strong&.configured? || false
    rescue StandardError
      false
    end

    def self.cache_key(user_id:, fingerprint:)
      [ "savings_opportunities", CACHE_VERSION, user_id, fingerprint ].join(":")
    end

    def initialize(user:, analysis:, cache: SharedCache.store, router: Ai::Router, ai_available: nil)
      @user = user
      @analysis = analysis
      @cache = cache
      @router = router
      @ai_available = ai_available
    end

    def ai_available?
      @ai_available.nil? ? self.class.ai_available? : @ai_available
    end

    def cache_key
      self.class.cache_key(user_id: user.id, fingerprint: analysis[:fingerprint])
    end

    def fetch
      cache.read(cache_key)
    end

    def generate!
      base = deterministic
      return persist(base) unless ai_usable?

      result = router.call(
        task: :savings_opportunity_analysis,
        input: ai_input,
        context: { user: user, allowed_references: base["highlights"].keys }
      )

      return persist(base.merge("error" => result.error.to_s.truncate(200))) unless result.ok?

      persist(merge_ai(base, result.data))
    rescue StandardError => e
      fallback = base || {
        "source" => "deterministic",
        "state" => analysis[:state].to_s,
        "summary" => t("narrative.summary_unavailable"),
        "highlights" => {},
        "generated_at" => Time.current.iso8601,
        "error" => nil
      }
      persist(fallback.merge("error" => "#{e.class}: #{e.message}".truncate(200)))
    end

    def deterministic
      highlights = {}
      analysis[:categories][:opportunities].each do |row|
        highlights["category:#{row[:id]}"] = category_highlight(row)
      end
      analysis[:recurring][:rows].each do |row|
        highlights["recurring:#{row[:key]}"] = recurring_highlight(row)
      end
      analysis[:small_expenses][:groups].each do |group|
        highlights["small:#{group[:key]}"] = small_highlight(group)
      end

      {
        "source" => "deterministic",
        "state" => analysis[:state].to_s,
        "summary" => summary,
        "highlights" => highlights,
        "generated_at" => Time.current.iso8601,
        "error" => nil
      }
    end

    private

    def persist(payload)
      cache.write(cache_key, payload, expires_in: CACHE_TTL)
      payload
    end

    def ai_usable?
      ai_available? && analysis[:state] == :ok && analysis[:totals][:opportunities_count].positive?
    end

    def summary
      totals = analysis[:totals]

      return t("narrative.summary_empty") if analysis[:state] == :empty
      return insufficient_summary(totals) if analysis[:state] == :insufficient_history
      return t("narrative.summary_none") if totals[:opportunities_count].zero?

      t("narrative.summary", opportunities: totals[:opportunities_count], detail: summary_detail(totals))
    end

    def insufficient_summary(totals)
      count = totals[:configured_recurring_count].to_i
      return t("narrative.summary_insufficient") unless count.positive?

      t("narrative.summary_insufficient_recurring", count: count)
    end

    def summary_detail(totals)
      parts = []
      if totals[:categories_count].positive?
        parts << t("narrative.detail_categories", count: totals[:categories_count])
      end
      if totals[:recurring_count].positive?
        parts << t("narrative.detail_recurring", count: totals[:recurring_count])
      end
      if totals[:small_expenses_count].positive?
        parts << t("narrative.detail_small", count: totals[:small_expenses_count])
      end
      parts.join(" ")
    end

    def category_highlight(row)
      explanation =
        if row[:comparable_average].positive? && row[:delta_pct].present?
          t("narrative.category.increased", name: row[:name], delta: percentage(row[:delta_pct]))
        elsif row[:comparable_average].zero?
          t("narrative.category.new", name: row[:name], share: percentage(row[:share_pct]))
        else
          t("narrative.category.significant", name: row[:name], share: percentage(row[:share_pct]))
        end

      {
        "explanation" => explanation,
        "recommendation" => row[:tip].presence ||
          t("narrative.category.recommendation", rate: row[:suggested_percentage].to_i,
            amount: MoneyFormat.currency(row[:potential]))
      }
    end

    def recurring_highlight(row)
      explanation =
        if row[:confidence] == :configured
          t("narrative.recurring.configured_explanation", name: row[:name],
            frequency: t("frequencies.#{row[:frequency]}", default: row[:frequency]))
        else
          t("narrative.recurring.explanation", name: row[:name],
            frequency: t("frequencies.#{row[:frequency]}", default: row[:frequency]))
        end

      {
        "explanation" => explanation,
        "recommendation" => t("narrative.recurring.recommendation")
      }
    end

    def small_highlight(group)
      {
        "explanation" => t("narrative.small.explanation", name: group[:name], count: group[:count]),
        "recommendation" => t("narrative.small.recommendation")
      }
    end

    def merge_ai(base, data)
      data = {} unless data.is_a?(Hash)
      summary = data["summary"].to_s.strip.truncate(MAX_SUMMARY)
      return base.merge("error" => "invalid_ai_response") if summary.blank?

      highlights = base["highlights"].transform_values(&:dup)
      Array(data["highlights"]).each do |entry|
        next unless entry.is_a?(Hash)

        reference = entry["reference"].to_s
        next unless highlights.key?(reference)

        explanation = entry["explanation"].to_s.strip.truncate(MAX_TEXT)
        recommendation = entry["recommendation"].to_s.strip.truncate(MAX_TEXT)
        highlights[reference] = {
          "explanation" => explanation.presence || highlights[reference]["explanation"],
          "recommendation" => recommendation.presence || highlights[reference]["recommendation"]
        }
      end

      base.merge("source" => "ai", "summary" => summary, "highlights" => highlights, "error" => nil)
    end

    def ai_input
      {
        "period" => analysis[:window_label],
        "categories" => analysis[:categories][:opportunities].map do |row|
          {
            "reference" => "category:#{row[:id]}",
            "name" => row[:name].to_s.truncate(80),
            "current" => row[:current].to_s("F"),
            "monthly_average" => row[:comparable_average].to_s("F"),
            "variation_pct" => row[:delta_pct],
            "share_pct" => row[:share_pct],
            "suggested_reduction_pct" => row[:suggested_percentage].to_i,
            "potential_monthly" => row[:potential].to_s("F")
          }
        end,
        "recurring" => analysis[:recurring][:rows].map do |row|
          {
            "reference" => "recurring:#{row[:key]}",
            "name" => row[:name].to_s.truncate(80),
            "frequency" => row[:frequency],
            "monthly_amount" => row[:monthly_amount].to_s("F"),
            "confidence" => row[:confidence].to_s,
            "occurrences" => row[:occurrences]
          }
        end,
        "small_expenses" => {
          "total" => analysis[:small_expenses][:total].to_s("F"),
          "count" => analysis[:small_expenses][:count],
          "groups" => analysis[:small_expenses][:groups].map do |group|
            {
              "reference" => "small:#{group[:key]}",
              "name" => group[:name].to_s.truncate(80),
              "count" => group[:count],
              "average" => group[:average].to_s("F"),
              "total" => group[:total].to_s("F")
            }
          end
        },
        "totals" => {
          "potential_monthly" => analysis[:totals][:potential_monthly].to_s("F"),
          "opportunities" => analysis[:totals][:opportunities_count]
        }
      }
    end

    def percentage(value)
      ActionController::Base.helpers.number_with_precision(value.to_f, precision: 1, separator: ",")
    end

    def t(key, **options)
      I18n.t("savings_opportunities.#{key}", **options)
    end
  end
end

# frozen_string_literal: true

module FinancialHabits
  class Narrative
    CACHE_VERSION = 1
    CACHE_TTL = 12.hours
    MAX_SUMMARY = 600
    MAX_TEXT = 400

    attr_reader :user, :analysis, :cache, :router

    def self.ai_available?
      Ai::Providers.strong&.configured? || false
    rescue StandardError
      false
    end

    def self.cache_key(user_id:, fingerprint:)
      [ "financial_habits", CACHE_VERSION, user_id, fingerprint ].join(":")
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
        task: :financial_habits_narrative,
        input: ai_input,
        context: { user: user, allowed_references: base["highlights"].keys }
      )

      return persist(base.merge("error" => result.error.to_s.truncate(200))) unless result.ok?

      persist(merge_ai(base, result.data))
    rescue StandardError => e
      fallback = base || {
        "source" => "deterministic",
        "state" => analysis[:state].to_s,
        "summary" => t("summary_empty"),
        "highlights" => {},
        "generated_at" => Time.current.iso8601,
        "error" => nil
      }
      persist(fallback.merge("error" => "#{e.class}: #{e.message}".truncate(200)))
    end

    def deterministic
      highlights = {}
      Array(analysis[:discoveries]).each do |discovery|
        highlights[discovery[:key].to_s] = {
          "explanation" => discovery[:description].to_s,
          "recommendation" => discovery[:recommendation].to_s
        }
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
      ai_available? && analysis[:state] == :ok && Array(analysis[:discoveries]).any?
    end

    def summary
      discoveries = Array(analysis[:discoveries])
      return t("summary_empty") if analysis[:state] == :empty
      return t("summary_insufficient") if analysis[:state] == :insufficient_data
      return t("summary_none") if discoveries.empty?

      t("summary", count: discoveries.size)
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
        "discoveries" => Array(analysis[:discoveries]).map do |discovery|
          {
            "reference" => discovery[:key].to_s,
            "title" => discovery[:title].to_s.truncate(80),
            "description" => discovery[:description].to_s.truncate(200),
            "confidence" => discovery[:confidence].to_s
          }
        end
      }
    end

    def t(key, **options)
      I18n.t("financial_habits.narrative.#{key}", default: key.to_s.humanize, **options)
    end
  end
end
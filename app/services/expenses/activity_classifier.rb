# frozen_string_literal: true

module Expenses
  # ActivityClassifier
  # Resolves the category for a transaction activity/merchant using stored
  # knowledge first so repeated activities never trigger repeat AI work.
  #
  # Lookup order: stored user correction → stored AI/rule knowledge →
  # deterministic category-name rule → nil (caller decides the fallback, e.g.
  # the AI-extracted category). Classifications are recorded back through
  # ActivityClassification so knowledge persists across imports.
  #
  # Example: Expenses::ActivityClassifier.call(user: user, activity: "DIDI FOOD")
  class ActivityClassifier
    def self.call(user:, activity:, record: true)
      new(user: user, activity: activity, record: record).resolve
    end

    def initialize(user:, activity:, record: true)
      @user = user
      @activity = activity.to_s
      @record = record
    end

    # Returns a result hash: { category:, category_name:, source: }.
    # source is one of cached_user, cached_ai, cached_rule, rule, fallback.
    def resolve
      cached = stored_classification
      return cached_result(cached) if cached&.category

      rule = rule_category
      if rule
        record_rule!(rule) if @record
        return { category: rule, category_name: rule.name, source: "rule" }
      end

      { category: nil, category_name: nil, source: "fallback" }
    end

    private

    def stored_classification
      ActivityClassification.lookup(user: @user, name: @activity)
    end

    def cached_result(classification)
      {
        category: classification.category,
        category_name: classification.category&.name,
        source: "cached_#{classification.source}"
      }
    end

    def rule_category
      normalized = ActivityClassification.normalize_name(@activity)
      return nil if normalized.blank?

      categories = Category.for_user(@user).where(category_type: "expense").to_a
      exact = categories.find { |category| ActivityClassification.normalize_name(category.name) == normalized }
      return exact if exact

      categories.find do |category|
        candidate = ActivityClassification.normalize_name(category.name)
        next false if candidate.blank? || candidate.length < 3

        normalized.include?(candidate)
      end
    end

    def record_rule!(category)
      ActivityClassification.record!(user: @user, name: @activity, category: category, source: "rule")
    rescue ActiveRecord::RecordInvalid, ArgumentError
      nil
    end
  end
end

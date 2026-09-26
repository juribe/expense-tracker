# frozen_string_literal: true

module Expenses
  module FileImport
    module Enrichers
      # Category classification. Priority: cached user overwrite → cached
      # AI/rule → rule → batch AI classification (deterministic imports
      # only) → whatever the base candidate already carries (statement
      # extractor result). Each unique activity is resolved once and reused
      # for the rest of the batch.
      class Activity
        include Expenses::ValueParsing

        def initialize(user:)
          @user = user
        end

        def call(candidates, engine)
          results = {}
          fallbacks = {}
          candidates.each do |candidate|
            activity = candidate.description.to_s
            next if activity.blank?

            key = normalize_name(activity) || activity
            result = results[key] ||= Expenses::ActivityClassifier.call(user: @user, activity: activity)

            if result[:source] == "fallback"
              fallbacks[key] = activity
              candidate.classification_source = engine == :ai ? "ai" : "fallback"
              candidate.suggested_category_id = candidate.category_id
              candidate.suggested_category_name = candidate.category_name
              next
            end

            candidate.classification_source = result[:source]
            candidate.suggested_category_id = result[:category].id if result[:category]
            candidate.suggested_category_name = result[:category]&.name
            next unless result[:category]

            candidate.category_id = result[:category].id
            candidate.category_name = result[:category].name
          end

          ai_classify_fallbacks(candidates, fallbacks, engine)
          candidates
        end

        private

        # Deterministic extraction (CSV/Excel) skips AI parsing, so without
        # classification reuse every row would land as "Others". Batch-classify
        # the activities with no stored/rule mapping in a single request (cheap
        # tier first when configured); learned classifications are persisted by
        # the classifier so the next import needs no AI at all.
        def ai_classify_fallbacks(candidates, fallbacks, engine)
          return if engine == :ai || fallbacks.empty?

          categories = Category.for_user(@user).where(category_type: "expense").order(:name)
          response = Ai::CategoryClassifier.new.call(activities: fallbacks.values.uniq,
                                                     categories: categories.map(&:name),
                                                     user: @user)
          return unless response[:ok?]

          assignments = response[:data] || {}
          candidates.each do |candidate|
            activity = candidate.description.to_s
            key = normalize_name(activity) || activity
            next unless fallbacks.key?(key)

            category_name = assignments[key].to_s.presence
            next unless category_name

            category = categories.find { |item| item.name.casecmp?(category_name) }
            next unless category

            candidate.category_id = category.id
            candidate.category_name = category.name
            candidate.suggested_category_id = category.id
            candidate.suggested_category_name = category.name
            candidate.classification_source = "ai"
          end
        end
      end
    end
  end
end

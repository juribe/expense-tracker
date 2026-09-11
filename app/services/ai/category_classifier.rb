# frozen_string_literal: true

module Ai
  # Batch classifier: maps a list of activity/merchant descriptions to one of
  # the user's categories in a single request, so deterministic file imports
  # (CSV/Excel) get the same kind of categorization the statement extractor
  # returns for PDFs without one AI call per transaction.
  #
  #   result = Ai::CategoryClassifier.new.call(activities: ["NETFLIX"], categories: ["Streaming", "Otros"])
  #     => { ok?: true, data: { "netflix" => "Streaming" }, error: nil }
  class CategoryClassifier
    class ExtractionError < StandardError; end

    class << self
      def parse(raw, activities:, categories:)
        new.parse_payload(raw, activities: activities, categories: categories)
      end
    end

    def parse_payload(raw, activities:, categories:)
      raise ExtractionError, "AI response is not a JSON object" unless raw.is_a?(Hash)

      assignments = raw["assignments"]
      raise ExtractionError, "missing 'assignments' array" unless assignments.is_a?(Array)

      allowed = categories.map { |category| [ category.to_s.downcase, category.to_s ] }.to_h
      lookup = activities.map { |activity| [ activity.to_s.downcase, activity_key(activity) ] }.to_h

      assignments.each_with_object({}) do |entry, map|
        next unless entry.is_a?(Hash)

        key = lookup[entry["activity"].to_s.downcase]
        category = allowed[entry["category"].to_s.downcase]
        next if key.nil? || category.nil?

        map[key] = category
      end
    end

    # Routes the batch through the cheap tier first (the stored-knowledge
    # cache is consulted even before that when a user is given) and escalates
    # to the strong tier on low confidence or failure. AI classifications are
    # persisted to ActivityClassification so future imports reuse them.
    #
    # Returns { ok?:, data: { normalized_activity => category_name },
    #           strategy: "cache"|"cheap_ai"|"strong_ai"|nil, error: }
    def call(activities:, categories:, user: nil)
      return { ok?: true, data: {}, strategy: nil, error: nil } if activities.empty? || categories.empty?

      result = Ai::Router.call(
        task: :category_classification,
        input: { activities: activities, categories: categories },
        context: { user: user }
      )
      return failure(result.error || "AI classification failed") unless result.ok?

      data = flatten_assignments(result.data)
      record_classifications(data, user: user, source: result.strategy)
      { ok?: true, data: data, strategy: result.strategy, error: nil }
    end

    private

    def flatten_assignments(data)
      (data || {}).each_with_object({}) do |(key, value), map|
        category = value.is_a?(Hash) ? value["category"] : value
        map[key] = category if category.present?
      end
    end

    def record_classifications(data, user:, source:)
      return if user.nil? || data.empty?
      return unless %w[cheap_ai strong_ai].include?(source.to_s)

      data.each do |key, category_name|
        ActivityClassification.record!(user: user, name: key, category: category_name, source: source)
      rescue ActiveRecord::RecordInvalid, ArgumentError
        nil
      end
    end

    def failure(message)
      { ok?: false, data: {}, strategy: nil, error: message }
    end

    def activity_key(activity)
      ActivityClassification.normalize_name(activity) || activity.to_s
    end
  end
end

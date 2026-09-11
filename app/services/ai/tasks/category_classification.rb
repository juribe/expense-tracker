# frozen_string_literal: true

module Ai
  module Tasks
    # Batch activity → category classification. Unique merchant/activity names
    # are classified in a single request so 1000 transactions with 5 unique
    # activities never cost 1000 AI calls.
    #
    # input:   { activities: ["DIDI FOOD", "UBER"], categories: ["Restaurants", ...] }
    # context: { user: } (optional; enables the stored-knowledge cache step)
    # data:    { "didi food" => { "category" => "Restaurants" }, ... }
    class CategoryClassification < Base
      def timeout
        40
      end

      # When every activity already has a stored classification, no AI call
      # happens at all.
      def cache_lookup(input, context)
        user = context[:user]
        return nil if user.nil?

        resolved = {}
        Array(input[:activities]).each do |activity|
          stored = ActivityClassification.lookup(user: user, name: activity)
          return nil unless stored&.category

          resolved[activity_key(activity)] = { "category" => stored.category.name }
        end
        return nil if resolved.empty?

        { data: resolved, confidence: 1.0 }
      end

      def messages(input, _context)
        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_content(Array(input[:activities]), Array(input[:categories])) }
        ]
      end

      def parse(content, input, _context)
        payload = parse_json(content)
        assignments = payload["assignments"]
        raise InvalidResponse, "missing 'assignments' array" unless assignments.is_a?(Array)

        activities = Array(input[:activities])
        categories = Array(input[:categories])

        allowed = categories.map { |category| [ category.to_s.downcase, category.to_s ] }.to_h
        lookup = activities.map { |activity| [ activity.to_s.downcase, activity_key(activity) ] }.to_h

        data = {}
        confidences = []
        assignments.each do |entry|
          next unless entry.is_a?(Hash)

          key = lookup[entry["activity"].to_s.downcase]
          category = allowed[entry["category"].to_s.downcase]
          next if key.nil?

          confidences << (entry["confidence"].is_a?(Numeric) ? Float(entry["confidence"]).clamp(0.0, 1.0) : 0.5)
          data[key] = { "category" => category }
        end

        { data: data, confidence: confidences.min }
      end

      private

      def activity_key(activity)
        ActivityClassification.normalize_name(activity) || activity.to_s
      end

      def system_prompt
        <<~PROMPT
          You classify merchant/activity names from bank transactions into ONE of the provided
          expense categories.
          Rules:
          - Use exactly one category name from the given list, spelled exactly as provided.
          - Use null (not a string) when no category fits.
          - Include a confidence between 0 and 1 for every assignment; reserve values below
            0.9 for genuinely ambiguous activities.
          - Return one assignment per activity, keeping the activity text exactly as received.
          Respond with ONLY JSON of the shape:
          {"assignments":[{"activity":"DIDI FOOD","category":"Restaurants","confidence":0.98},
            {"activity":"ACME INSURANCE","category":null,"confidence":0.2}]}
        PROMPT
      end

      def user_content(activities, categories)
        <<~PROMPT
          Categories (use one of them verbatim): #{categories.join(", ")}

          Activities to classify:
          #{activities.each_with_index.map { |activity, index| "#{index + 1}. #{activity}" }.join("\n")}
        PROMPT
      end
    end
  end
end

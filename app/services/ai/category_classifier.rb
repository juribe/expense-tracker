# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

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

    def call(activities:, categories:)
      return { ok?: true, data: {}, error: nil } if activities.empty? || categories.empty?

      if api_key.blank?
        return failure("AI classification is not configured (missing MISTRAL_API_KEY).")
      end

      { ok?: true, data: self.class.parse(request_classification(activities, categories), activities: activities, categories: categories), error: nil }
    rescue ExtractionError => e
      failure(e.message)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      failure("AI request failed (#{e.message})")
    end

    private

    def failure(message)
      { ok?: false, data: {}, error: message }
    end

    def api_key
      ENV["MISTRAL_API_KEY"].presence
    end

    def activity_key(activity)
      ActivityClassification.normalize_name(activity) || activity.to_s
    end

    def request_classification(activities, categories)
      uri = URI(ENV.fetch("MISTRAL_BASE_URL", "https://api.mistral.ai/v1/chat/completions"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 40

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = {
        model: ENV.fetch("MISTRAL_MODEL", "mistral-small-latest"),
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_content(activities, categories) }
        ]
      }.to_json

      response = http.request(request)
      unless response.code.to_i == 200
        raise ExtractionError, "AI classification failed (HTTP #{response.code})"
      end

      content = JSON.parse(response.body).dig("choices", 0, "message", "content")
      raise ExtractionError, "AI response content is empty" if content.blank?
      JSON.parse(content)
    rescue JSON::ParserError, TypeError, KeyError => e
      raise ExtractionError, "invalid AI response (#{e.message})"
    end

    def user_content(activities, categories)
      <<~PROMPT
        Categories (use one of them verbatim): #{categories.join(", ")}

        Activities to classify:
        #{activities.each_with_index.map { |activity, index| "#{index + 1}. #{activity}" }.join("\n")}
      PROMPT
    end

    def system_prompt
      <<~PROMPT
        You classify merchant/activity names from bank transactions into ONE of the provided
        expense categories.
        Rules:
        - Use exactly one category name from the given list, spelled exactly as provided.
        - Use null (not a string) when no category fits.
        - Return one assignment per activity, keeping the activity text exactly as received.
        Respond with ONLY JSON of the shape:
        {"assignments":[{"activity":"DIDI FOOD","category":"Restaurants"},
          {"activity":"ACME INSURANCE","category":null}]}
      PROMPT
    end
  end
end

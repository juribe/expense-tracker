# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Ai
  # Extracts an expense from a receipt / payment image using Mistral's vision
  # model. The first pass reads the visible text (OCR), the model then returns
  # structured expense fields with strict JSON output.
  #
  #   result = Ai::ImageExpenseExtractor.new.call(image_data:, context_text: nil, today: Date.current)
  #     => { ok?: true,
  #          data: { ocr_text: "SUPERMERCADO ÉXITO ...", expenses: [ {...} ] },
  #          error: nil }
  class ImageExpenseExtractor
    class ExtractionError < StandardError; end

    DEFAULT_CURRENCY = "COP"

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(image_data:, context_text: nil, today: Date.current)
      @image_data = image_data
      @context_text = context_text
      @today = today
    end

    def call
      return failure("AI extraction is not configured (missing MISTRAL_API_KEY).") if api_key.blank?

      data = parse_response(request_extraction)
      { ok?: true, data: data, error: nil }
    rescue ExtractionError => e
      failure(e.message)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      failure("AI request failed (#{e.message})")
    end

    private

    def failure(message)
      { ok?: false, data: nil, error: message }
    end

    def api_key
      ENV["MISTRAL_API_KEY"].presence
    end

    def request_extraction
      uri = URI(ENV.fetch("MISTRAL_BASE_URL", "https://api.mistral.ai/v1/chat/completions"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 45

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = {
        model: ENV.fetch("MISTRAL_VISION_MODEL", "pixtral-12b-24091063"),
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_content }
        ]
      }.to_json

      response = perform_request(http, request)

      content = JSON.parse(response.body).dig("choices", 0, "message", "content")
      JSON.parse(content)
    rescue JSON::ParserError, TypeError, KeyError => e
      raise ExtractionError, "invalid AI response (#{e.message})"
    end

    # Retries rate-limited (HTTP 429) responses with a short backoff; other
    # HTTP errors fail immediately. Accepts a callable so tests can stub HTTP.
    def perform_request(http, request)
      retry_with_backoff { http.request(request) }
    end

    def retry_with_backoff
      attempts = 0
      loop do
        response = yield
        return response if response.code.to_i == 200

        if response.code.to_i == 429 && attempts < 2
          attempts += 1
          sleep(attempts)
          next
        end

        raise ExtractionError, "AI HTTP #{response.code}"
      end
    end

    def user_content
      content = []
      content << { type: "text", text: context_text_block } if @context_text.present?
      content << { type: "image_url", image_url: @image_data }
      content
    end

    def context_text_block
      <<~TEXT
        Additional context provided by the user:
        #{@context_text.to_s[0, 1000]}
      TEXT
    end

    def system_prompt
      <<~PROMPT
        You read receipt / payment images and extract the expense they represent.
        First transcribe ALL visible text of the image into "ocr_text" (line by line, verbatim).
        Then extract ONE expense from the image (or from the user's context when the image alone is ambiguous).
        Rules:
        - Interpret Colombian amounts: "87.500" = 87500, "8,500" = 8500.
        - Prefer the TOTAL line when a receipt shows items plus a total.
        - Resolve the date to an ISO date (YYYY-MM-DD); when no date is visible use #{@today.iso8601}.
        - Category must be a short english hint such as: groceries, restaurants, transportation, shopping, utilities, health, entertainment.
        Respond with ONLY JSON of the shape:
        {"ocr_text":"...","expenses":[{"amount":87500,"currency":"COP","merchant":"Supermercado Éxito",
          "description":"Compra supermercado","category":"groceries","transaction_date":"#{@today.iso8601}",
          "confidence":0.9}]}
        When no expense can be extracted respond with {"ocr_text":"...","expenses":[]}.
      PROMPT
    end

    def parse_response(raw)
      raise ExtractionError, "AI response is not a JSON object" unless raw.is_a?(Hash)

      ocr_text = raw["ocr_text"].to_s.strip
      entries = raw["expenses"]
      raise ExtractionError, "missing 'expenses' array" unless entries.is_a?(Array)

      { ocr_text: ocr_text, expenses: entries.filter_map { |entry| normalize_entry(entry) } }
    end

    def normalize_entry(entry)
      return nil unless entry.is_a?(Hash)

      amount = parse_amount(entry["amount"])
      date = parse_date(entry["transaction_date"])
      return nil if amount.nil?

      {
        amount: amount,
        currency: normalize_currency(entry["currency"]),
        merchant: entry["merchant"].to_s.strip.presence,
        description: entry["description"].to_s.strip.presence,
        category_name: entry["category"].to_s.strip.presence,
        create_category: false,
        transaction_date: date&.iso8601,
        confidence: normalize_confidence(entry["confidence"])
      }
    end

    def parse_amount(value)
      numeric =
        case value
        when Numeric
          value.to_f
        else
          parse_amount_text(value.to_s)
        end
      return nil unless numeric.is_a?(Numeric) && numeric.positive? && numeric.finite?

      BigDecimal(numeric.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_amount_text(text)
      return 0.0 if text.blank?

      if text.match?(/\A\d{1,3}(?:\.\d{3})+\z/)
        text.delete(".").to_f
      elsif text.match?(/\A\d+(?:,\d{1,2})\z/)
        text.tr(",", ".").to_f
      else
        text.gsub(/[^0-9.\-]/, "").to_f
      end
    end

    def parse_date(value)
      return @today if value.blank?

      begin
        Date.iso8601(value.to_s)
      rescue ArgumentError, Date::Error, TypeError
        Date.parse(value.to_s)
      end
    rescue ArgumentError, Date::Error, TypeError
      nil
    end

    def normalize_currency(value)
      currency = value.to_s.strip.upcase
      currency.match?(/\A[A-Z]{3}\z/) ? currency : DEFAULT_CURRENCY
    end

    def normalize_confidence(value)
      confidence = value.is_a?(Numeric) ? value : Float(value.to_s)
      confidence.clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      0.5
    end
  end
end

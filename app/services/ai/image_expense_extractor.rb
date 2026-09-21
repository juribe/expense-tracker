# frozen_string_literal: true

require "json"

module Ai
  # Extracts an expense from a receipt / payment image using the strong-tier
  # provider's vision model. The first pass reads the visible text (OCR), the
  # model then returns structured expense fields with strict JSON output.
  #
  #   result = Ai::ImageExpenseExtractor.new.call(image_data:, context_text: nil, today: Date.current)
  #     => { ok?: true,
  #          data: { ocr_text: "SUPERMERCADO ÉXITO ...", expenses: [ {...} ] },
  #          error: nil }
  class ImageExpenseExtractor
    class ExtractionError < StandardError; end

    DEFAULT_CURRENCY = "COP"
    TASK = "image_extraction"
    # One retry covers the model occasionally stopping mid-generation
    # (finish_reason "error"), which cuts the JSON payload mid-string, or
    # drifting away from the required JSON shape. The retry re-sends the
    # request with a corrective instruction (temperature 0 would otherwise
    # reproduce the same broken output verbatim).
    MAX_ATTEMPTS = 2
    # Generous explicit cap so no provider default can truncate a receipt's
    # verbatim ocr_text.
    MAX_TOKENS = 4096
    CORRECTIVE_SUFFIX =
      "Your previous response was invalid: it was truncated or did not follow the required shape. " \
      "Respond again with ONLY a JSON object with EXACTLY two top-level keys, \"ocr_text\" and \"expenses\". " \
      "Transcribe the visible text ONCE and never add other top-level keys."

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(image_data:, context_text: nil, user: nil, today: Date.current)
      @image_data = image_data
      @context_text = context_text
      @user = user
      @today = today
    end

    def call
      started = monotonic
      provider = Ai::Providers.strong
      return failure("AI extraction is not configured (missing MISTRAL_API_KEY).") unless provider.configured?

      response = nil
      data = nil
      parse_error = nil
      MAX_ATTEMPTS.times do |attempt|
        response = provider.chat(
          messages: chat_messages(corrective: attempt.positive?),
          model: Ai.configuration.vision_model,
          timeout: 45,
          max_tokens: MAX_TOKENS
        )
        begin
          data = parse_response(JSON.parse(response.content))
          parse_error = nil
          break
        rescue JSON::ParserError, TypeError, KeyError, ExtractionError => e
          parse_error = e
          data = nil
        end
      end

      if data
        record(provider, response: response, data: data, latency_ms: latency_since(started))
        { ok?: true, data: data, error: nil }
      else
        message = parse_error ? "invalid AI response (#{parse_error.message})" : "invalid AI response (empty content)"
        record(provider, response: response, error: message, latency_ms: latency_since(started))
        failure(message)
      end
    rescue Ai::Provider::Error => e
      record(provider, error: e.message, latency_ms: latency_since(started))
      failure(e.message)
    end

    private

    def failure(message)
      { ok?: false, data: nil, error: message }
    end

    def record(provider, response: nil, data: nil, error: nil, latency_ms: nil)
      Ai::Recorder.write(
        task: TASK, user: @user, strategy: "strong_ai", provider: provider,
        status: error ? "error" : "ok",
        confidence: data ? overall_confidence(data) : nil,
        escalated: false,
        error: error, input_tokens: response&.input_tokens,
        output_tokens: response&.output_tokens, latency_ms: latency_ms,
        prompt: recordable_prompt,
        output: response&.content
      )
    end

    def overall_confidence(data)
      data[:expenses].filter_map { |entry| entry[:confidence] }.min
    end

    # The multimodal payload (base64 image) is never stored: the recorded
    # prompt keeps the system instructions and a size note for the image.
    def recordable_prompt
      [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt_summary }
      ]
    end

    def user_prompt_summary
      summary = +"(image attached, #{(@image_data.to_s.length / 1024)} KB base64)"
      summary << " + user note: #{@context_text.to_s[0, 300]}" if @context_text.present?
      summary
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def latency_since(started)
      ((monotonic - started) * 1000).round
    end

    def chat_messages(corrective: false)
      [
        { role: "system", content: system_prompt },
        { role: "user", content: user_content(corrective) }
      ]
    end

    def user_content(corrective)
      text = +""
      text << context_text_block if @context_text.present?
      text << CORRECTIVE_SUFFIX if corrective

      content = []
      content << { type: "text", text: text } if text.present?
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
        You read receipt / payment screenshots and extract the money movement they represent (a purchase, a transfer, a payment confirmation, ...).

        Respond with ONLY a JSON object with EXACTLY two top-level keys:
        {"ocr_text":"...","expenses":[...]}

        - "ocr_text": ALL visible text of the image, transcribed ONCE, line by line, verbatim. Never repeat lines or sections, and never add other top-level keys to the JSON.
        - "expenses": ONE expense extracted from the image (or from the user's context when the image alone is ambiguous), or an empty array when nothing can be extracted.
          Each expense: {"amount":87500,"currency":"COP","merchant":"Supermercado Éxito",
          "description":"Compra supermercado","category":"groceries","transaction_date":"#{@today.iso8601}",
          "confidence":0.9}

        Rules:
        - Interpret Colombian amounts: "87.500" = 87500, "8,500" = 8500.
        - Prefer the TOTAL line when a receipt shows items plus a total; for transfer / payment confirmations use the transferred amount.
        - A money-transfer or payment-confirmation screen (e.g. Nequi, Bancolombia) IS an expense.
        - Resolve the date to an ISO date (YYYY-MM-DD); when no date is visible use #{@today.iso8601}.
        - Category must be a short english hint such as: groceries, restaurants, transportation, shopping, utilities, health, entertainment.
        - Output only valid JSON: no markdown, no explanations, no extra keys.
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

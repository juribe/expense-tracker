# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Ai
  # Extracts structured financial transactions from an email using an LLM with
  # strict JSON output (same Mistral endpoint used by ExpenseParser).
  #
  #   result = Ai::TransactionExtractor.new.call(subject:, body:, today: Date.current)
  #     => { ok?: true,
  #          data: { transactions: [ { type:, amount:, currency:, merchant:,
  #                                   category:, occurred_at:, confidence:,
  #                                   card_last_four:, bank:, transaction_type: } ],
  #                  should_ignore: false, reason: nil },
  #          error: nil }
  class TransactionExtractor
    AUTO_TYPES = %w[expense].freeze
    KNOWN_TYPES = %w[expense refund reversal failed other].freeze
    DEFAULT_CURRENCY = "COP"

    class ExtractionError < StandardError; end

    class << self
      # Validates + normalizes a raw AI payload into the canonical structure.
      # Raises ExtractionError when the payload is unusable.
      def parse(raw, today: Date.current)
        new.parse_payload(raw, today)
      end
    end

    def parse_payload(raw, today)
      raise ExtractionError, "AI response is not a JSON object" unless raw.is_a?(Hash)

      should_ignore = raw["should_ignore"].nil? ? false : !!raw["should_ignore"]
      reason = normalize_reason(raw["reason"])

      entries = raw["transactions"]
      raise ExtractionError, "missing 'transactions' array" unless entries.is_a?(Array)

      transactions = entries.filter_map { |entry| normalize_transaction(entry, today) }

      if !should_ignore && transactions.empty?
        raise ExtractionError, "no valid transactions extracted"
      end

      {
        transactions: transactions,
        should_ignore: should_ignore || transactions.empty?,
        reason: reason
      }
    end

    def call(subject:, body:, today: Date.current)
      if api_key.blank?
        return failure("AI extraction is not configured (missing MISTRAL_API_KEY).")
      end

      data = self.class.parse(request_extraction(subject, body), today: today)
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

    def request_extraction(subject, body)
      uri = URI(ENV.fetch("MISTRAL_BASE_URL", "https://api.mistral.ai/v1/chat/completions"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 25

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = {
        model: ENV.fetch("MISTRAL_MODEL", "mistral-small-latest"),
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: email_content(subject, body) }
        ]
      }.to_json

      response = http.request(request)
      raise ExtractionError, "AI HTTP #{response.code}" unless response.code.to_i == 200

      content = JSON.parse(response.body).dig("choices", 0, "message", "content")
      JSON.parse(content)
    rescue JSON::ParserError, TypeError, KeyError => e
      raise ExtractionError, "invalid AI response (#{e.message})"
    end

    def email_content(subject, body)
      <<~CONTENT
        Email subject: #{subject.to_s[0, 200]}
        Email body:
        #{body.to_s[0, 6000]}
      CONTENT
    end

    def system_prompt
      <<~PROMPT
        You analyze bank / credit-card notification emails and extract financial transactions.
        Decide whether the email reports money leaving the user's account.
        Rules:
        - Card purchases, debit transactions, approved payments and outgoing bank transfers are expenses.
        - Credit card statements, payment reminders, minimum payment notices, promotions, marketing,
          balance notifications and security alerts must be ignored.
        - Refunds, reversed transactions and failed/declined charges must be reported with their type
          but they do not create expenses.
        - One email may contain several transactions; return one entry per transaction.
        - Amounts must be positive numbers in the smallest published unit shown by the bank
          ("$48.500" COP means 48500).
        - Use ISO datetimes for occurred_at. Category must be a short lowercase english hint such as:
          restaurants, groceries, transportation, shopping, utilities, health, entertainment.
        Respond with ONLY JSON of the shape:
        {"transactions":[{"type":"expense","amount":48500,"currency":"COP","merchant":"Restaurante XYZ",
          "category":"restaurants","occurred_at":"2026-08-23T14:30:00","confidence":0.98,
          "card_last_four":"1234","bank":"Bancolombia"}],
         "should_ignore":false,"reason":null}
        When nothing applies respond with {"transactions":[],"should_ignore":true,"reason":"..."}.
      PROMPT
    end

    # ------------------------------------------------------------- normalization

    def normalize_reason(value)
      value.is_a?(String) ? value.presence : nil
    end

    def normalize_transaction(entry, today)
      return nil unless entry.is_a?(Hash)

      amount = parse_amount(entry["amount"])
      merchant = entry["merchant"].to_s.strip
      occurred_at = parse_occurred_at(entry["occurred_at"], today)
      return nil if amount.nil? || merchant.blank?

      {
        type: normalize_type(entry["type"]),
        amount: amount,
        currency: normalize_currency(entry["currency"]),
        merchant: merchant,
        category: entry["category"].to_s.strip.presence || "others",
        occurred_at: occurred_at.iso8601,
        confidence: normalize_confidence(entry["confidence"]),
        card_last_four: normalize_card(entry["card_last_four"]),
        bank: entry["bank"].to_s.strip.presence
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

    # Handles plain numbers plus Colombian formatting: "48500", "48.500"
    # (thousands) and "48,50" (decimal comma).
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

    def normalize_type(value)
      type = value.to_s.downcase
      case type
      when "", "purchase", "compra", "debit", "débito", "cargo", "payment", "transfer"
        "expense"
      when *KNOWN_TYPES
        type
      else
        "other"
      end
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

    def normalize_card(value)
      digits = value.to_s.scan(/\d/).join
      digits[-4..]&.then { |last4| last4.length == 4 ? last4 : nil }
    end

    def parse_occurred_at(value, today)
      return Time.zone.now if value.blank?

      Time.zone.parse(value.to_s) || today.beginning_of_day
    rescue ArgumentError, TypeError
      today.beginning_of_day
    end
  end
end

# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Ai
  # Extracts financial sources and transactions from a statement document using
  # an LLM with strict JSON output (same Mistral endpoint as TransactionExtractor).
  #
  # Returns structured data only; it never creates or modifies records.
  #
  #   result = Ai::StatementExtractor.new.call(text: "...", today: Date.current)
  #     => { ok?: true, data: { sources: [ { ... } ], transactions: [ { ... } ] }, error: nil }
  class StatementExtractor
    DEFAULT_CURRENCY = "COP"

    class ExtractionError < StandardError; end

    class << self
      def parse(raw)
        new.parse_payload(raw)
      end
    end

    def parse_payload(raw)
      raise ExtractionError, "AI response is not a JSON object" unless raw.is_a?(Hash)

      sources_raw = raw["sources"]
      raise ExtractionError, "missing 'sources' array" unless sources_raw.is_a?(Array)

      sources = sources_raw.filter_map { |entry| normalize_source(entry) }

      transactions = []
      raw_transactions = raw["transactions"]
      if raw_transactions.is_a?(Array)
        transactions = raw_transactions.filter_map { |entry| normalize_transaction(entry) }
      end

      if sources.empty?
        raise ExtractionError, "no financial sources extracted"
      end

      { sources: sources, transactions: transactions }
    end

    def call(text:, today: Date.current)
      if api_key.blank?
        return failure("AI extraction is not configured (missing MISTRAL_API_KEY).")
      end

      data = self.class.parse(request_extraction(text))
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

    def request_extraction(text)
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
          { role: "user", content: "Statement contents:\n\n#{text.to_s[0, 12_000]}" }
        ]
      }.to_json

      response = http.request(request)
      raise ExtractionError, "AI HTTP #{response.code}" unless response.code.to_i == 200

      content = JSON.parse(response.body).dig("choices", 0, "message", "content")
      JSON.parse(content)
    rescue JSON::ParserError, TypeError, KeyError => e
      raise ExtractionError, "invalid AI response (#{e.message})"
    end

    def system_prompt
      <<~PROMPT
        You analyze bank, credit-card, or loan statement documents and extract the financial
        source(s) they belong to, plus any transactions shown.
        Identify the institution, account/card/loan type, an identifier or last-four digits when
        available, balances, credit limits, loan balances and payment information.
        Amounts are positive numbers in the smallest published unit shown ("$5.420.000" COP means 5420000).
        kind must be one of: account, credit_card, loan.
        Respond with ONLY JSON of the shape:
        {"sources":[{"kind":"account","name":"Cuenta de Ahorros","bank":"Bancolombia",
          "sub_kind":"savings","card_last_four":"1234","balance":5420000,
          "credit_limit":null,"outstanding_balance":null,"monthly_payment":null,
          "interest_rate":null,"interest_rate_type":null,"identifier":"1234"}],
         "transactions":[{"date":"2026-08-23","description":"Restaurante XYZ","amount":48500,
          "type":"expense","category":"restaurants","confidence":0.98}]}
        When a document contains no identifiable financial source, respond with {"sources":[]}.
      PROMPT
    end

    # ------------------------------------------------------------------ normalize

    def normalize_source(entry)
      return nil unless entry.is_a?(Hash)

      kind = entry["kind"].to_s.downcase
      return nil unless %w[account credit_card loan].include?(kind)

      name = entry["name"].to_s.strip
      bank = entry["bank"].to_s.strip.presence
      return nil if name.blank? && bank.blank?

      {
        kind: kind,
        name: name.presence || bank,
        bank: bank,
        sub_kind: entry["sub_kind"].to_s.strip.presence,
        card_last_four: normalize_card(entry["card_last_four"]),
        balance: parse_amount(entry["balance"]),
        credit_limit: parse_amount(entry["credit_limit"]),
        outstanding_balance: parse_amount(entry["outstanding_balance"]),
        monthly_payment: parse_amount(entry["monthly_payment"]),
        interest_rate: parse_amount(entry["interest_rate"]),
        interest_rate_type: normalize_rate_type(entry["interest_rate_type"]),
        identifier: entry["identifier"].to_s.strip.presence
      }
    end

    def normalize_transaction(entry)
      return nil unless entry.is_a?(Hash)

      description = entry["description"].to_s.strip
      amount = parse_amount(entry["amount"])
      return nil if description.blank? || amount.nil?

      {
        date: entry["date"].to_s.presence,
        description: description,
        amount: amount,
        type: normalize_type(entry["type"]),
        category: entry["category"].to_s.strip.presence || "others",
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
      return nil unless numeric.is_a?(Numeric) && numeric.finite?

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

    def normalize_type(value)
      type = value.to_s.downcase
      case type
      when "", "expense", "debit", "débito", "compra", "purchase"
        "expense"
      when "income", "credit", "abono"
        "income"
      else
        "expense"
      end
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

    def normalize_rate_type(value)
      type = value.to_s.downcase.gsub(/\s+/, "_")
      return type if %w[effective_annual nominal_annual monthly].include?(type)

      nil
    end
  end
end

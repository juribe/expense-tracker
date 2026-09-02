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

    STATEMENT_CHAR_LIMIT = 12_000
    STATEMENT_HEAD_CHARS = 8_000
    STATEMENT_TAIL_CHARS = 4_000

    ACCOUNT_NUMBER_LABEL = /(?:n[uú]mero|nro\.?|no\.?|n[oº°]|\#)\s*(?:de\s+)?cuenta|cuenta\s*(?:n[uú]mero|nro\.?|no\.?|n[oº°]|\#)|account\s*(?:number|no\.?|\#)/i
    CARD_NUMBER_LABEL = /(?:n[uú]mero|nro\.?|no\.?|n[oº°]|\#)\s*(?:de\s+)?tarjeta|card\s*(?:number|no\.?|\#)/i
    LOAN_NUMBER_LABEL = /(?:n[uú]mero|nro\.?|no\.?|n[oº°]|\#)\s*(?:de\s+)?(?:cr[eé]dito|pr[eé]stamo|contrato)|contrato\s*(?:n[uú]mero|nro\.?|no\.?|n[oº°]|\#)|loan\s*(?:number|no\.?|\#)/i
    LABELED_NUMBER = /([*\d][\d\s\-*.]{4,32}[\d*])/

    class << self
      def parse(raw, text: nil)
        new.parse_payload(raw, text: text)
      end
    end

    def parse_payload(raw, text: nil)
      raise ExtractionError, "AI response is not a JSON object" unless raw.is_a?(Hash)

      sources_raw = raw["sources"]
      raise ExtractionError, "missing 'sources' array" unless sources_raw.is_a?(Array)

      sources = sources_raw.filter_map { |entry| normalize_source(entry) }
      sources = apply_labeled_identifiers(sources, text) if text.present?
      sources = repair_amounts_from_text(sources, text) if text.present?

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

      data = self.class.parse(request_extraction(text), text: text)
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
          { role: "user", content: "Statement contents:\n\n#{statement_window(text)}" }
        ]
      }.to_json

      response = nil
      attempts = 0
      loop do
        attempts += 1
        begin
          response = http.request(request)
        rescue Net::OpenTimeout, Net::ReadTimeout
          response = nil
        end

        break if attempts > 2
        break if response.nil? == false && response.code.to_i < 500

        sleep(2**attempts)
      end

      raise ExtractionError, "AI HTTP #{response.code}" unless response&.code.to_i == 200

      content = JSON.parse(response.body).dig("choices", 0, "message", "content")
      raise ExtractionError, "AI response content is empty" if content.blank?
      JSON.parse(content)
    rescue JSON::ParserError, TypeError, KeyError => e
      raise ExtractionError, "invalid AI response (#{e.message})"
    end

    def statement_window(text)
      str = text.to_s
      return str if str.length <= STATEMENT_CHAR_LIMIT

      "#{str[0, STATEMENT_HEAD_CHARS]}\n\n[...]\n\n#{str[-STATEMENT_TAIL_CHARS, STATEMENT_TAIL_CHARS]}"
    end

    def system_prompt
      <<~PROMPT
        You analyze bank, credit-card, or loan statement documents and extract the financial
        source(s) they belong to, plus any transactions shown.
        Identify the institution, account/card/loan type, identifier, balances, credit limits,
        loan balances and payment information.
        Amounts are positive numbers in the smallest published unit shown ("$5.420.000" COP means 5420000).
        AMOUNT PRECISION — amounts printed like "19.877.599,71" have a decimal part. Return
        19877599.71 (keeping the decimals). NEVER join the decimal digits into the integer part
        (1987759971 is WRONG). When in doubt, return the number exactly as the digits before the
        decimal separator, with the digits after it as decimals.
        kind must be one of: account, credit_card, loan.

        REVOLVING LINE OF CREDIT — a "crédito rotativo" / "línea de crédito rotativa" /
        revolving credit line is a LOAN, NEVER a credit card. Classify it as kind="loan"
        even when the document shows a card number, a "cupo", or revolving interest.

        IDENTIFIERS — follow the kind exactly:
        ACCOUNT (cuenta bancaria / savings / checking):
          - Look for the "número de cuenta" / "Nro. de cuenta" / "Cuenta No." /
            "Account number" (typically 8–20 digits).
          - identifier MUST be ONLY the last four digits of the account number
            (privacy — the full number is never stored), just like credit cards.
          - card_last_four MUST be those same last four digits.
          - If a debit-card number also appears, IGNORE it. The account number wins.
          - Do NOT use NIT, cédula, número de transacción, referencia de pago, número de extracto,
            or contrato as the account identifier.

        CREDIT CARD:
          - Look for "Número de tarjeta" / "No. tarjeta" / "Card number" (often at the end).
          - card_last_four = ONLY its last four digits. identifier = those same last four.
          - NEVER return the full card number.
          - Prefer the card number over contrato / referencia.

        MONEY FIELDS — map the printed labels to fields, keep amounts positive:
          CREDIT CARD:
            - credit_limit = the total credit line: "CUPO ASIGNADO", "Cupo asignado", "Cupo total",
              "Límite de crédito", "Cupo".
            - balance = the current DEBT owed by the client (money used), NOT the available credit:
              "Saldo actual", "Saldo de deuda", "Saldo total", "Deuda", "Saldo del periodo".
              Do NOT return "Cupo disponible" / available credit as balance.
          LOAN:
            - principal_amount = the total money originally disbursed to the client:
              "Valor desembolsado", "Monto desembolsado", "Capital desembolsado",
              "Valor del crédito", "Valor del préstamo".
            - outstanding_balance = what is still owed: "Saldo capital", "Saldo actual",
              "Saldo pendiente", "Saldo de capital".
            - monthly_payment = "Cuota mensual", "Valor cuota", "Cuota fija", "Cuota mínima".
            - installment_count = the TOTAL number of installments of the credit:
              "Número de cuotas", "Total de cuotas", "Cuotas totales", "Plazo en cuotas".
            - installments_paid = how many installments the client has already paid
              (which installment the loan is on now): "Cuotas pagadas", "Cuota actual No.",
              "Cuotas canceladas", "Cuotas pagadas a la fecha".
            - For revolving lines (crédito rotativo): credit_limit = "CUPO ASIGNADO" / "Cupo total",
              outstanding_balance = "Saldo actual" / "Saldo de deuda", and principal_amount is
              the originally disbursed value when printed.

        LOAN:
          - identifier MUST be ONLY the last four digits of the contract / credit / loan
            number. card_last_four = null. (privacy — the full number is never stored)
          - For a revolving line, prefer the "crédito" / contract number over any card number.

        Respond with ONLY JSON of the shape:
        {"sources":[{"kind":"account","name":"Cuenta de Ahorros","bank":"Bancolombia",
          "sub_kind":"savings","card_last_four":"5689","balance":5420000,
          "credit_limit":null,"outstanding_balance":null,"monthly_payment":null,
          "interest_rate":null,"interest_rate_type":null,"identifier":"5689"},
         {"kind":"loan","name":"Libre Inversión","bank":"Bancolombia","principal_amount":8000000,
          "outstanding_balance":6000000,"monthly_payment":350000,"installment_count":36}],
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

      raw_name = entry["name"].to_s.strip
      bank = entry["bank"].to_s.strip.presence
      name = raw_name unless card_number?(raw_name)
      return nil if name.blank? && bank.blank?

      identifier, card_last_four = normalize_source_ids(kind, entry)

      {
        kind: kind,
        name: name.presence || bank,
        bank: bank,
        sub_kind: entry["sub_kind"].to_s.strip.presence,
        card_last_four: card_last_four,
        # Loans have no "balance" concept in our model (outstanding_balance is
        # what is owed); nil out whatever the AI returns there to avoid junk.
        balance: kind == "loan" ? nil : parse_amount(entry["balance"]),
        credit_limit: parse_amount(entry["credit_limit"]),
        outstanding_balance: parse_amount(entry["outstanding_balance"]),
        monthly_payment: parse_amount(entry["monthly_payment"]),
        principal_amount: parse_amount(entry["principal_amount"]),
        installment_count: normalize_count(entry["installment_count"]),
        installments_paid: normalize_count(entry["installments_paid"]),
        interest_rate: parse_amount(entry["interest_rate"]),
        interest_rate_type: normalize_rate_type(entry["interest_rate_type"]),
        identifier: identifier
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

    # Colombian rule: "." is the thousands separator, "," the decimal one.
    # Handles "5.420.000", "1234,92" and the mixed "67.429.112,92".
    def parse_amount_text(text)
      return 0.0 if text.blank?

      cleaned = text.gsub(/[^0-9.,\-]/, "")
      return 0.0 if cleaned.blank? || cleaned == "-"

      if cleaned.match?(/\A-?\d{1,3}(?:\.\d{3})+,\d+\z/)
        # "67.429.112,92" — dot thousands + comma decimals
        cleaned.delete(".").tr(",", ".").to_f
      elsif cleaned.match?(/\A-?\d{1,3}(?:\.\d{3})+\z/)
        # "5.420.000" — dot thousands only
        cleaned.delete(".").to_f
      elsif cleaned.match?(/\A-?\d+,\d+\z/)
        # "1234,92" — comma is the decimal separator
        cleaned.tr(",", ".").to_f
      else
        cleaned.to_f
      end
    end

    # Integer counts (e.g. "48 cuotas", "Número de cuotas: 24").
    def normalize_count(value)
      value.to_s.scan(/\d/).join.presence&.to_i
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

    def normalize_source_ids(kind, entry)
      raw_identifier = digits_only(entry["identifier"])
      card_last_four = normalize_card(entry["card_last_four"])

      case kind
      when "account"
        # SECURITY: never keep a full account number. Store the last four digits
        # only (like cards). Keep a short identifier intact for dedup.
        last4 = normalize_card(raw_identifier)
        [ last4 || raw_identifier, last4 ]
      when "credit_card"
        card_last_four ||= normalize_card(raw_identifier)
        # SECURITY: never keep a full credit-card number. Identifier is last four only.
        [ card_last_four, card_last_four ]
      else
        # SECURITY: never keep a full loan / contract number. Store the last
        # four digits only, consistent with accounts and credit cards.
        [ normalize_card(raw_identifier), nil ]
      end
    end

    def apply_labeled_identifiers(sources, text)
      hints = labeled_identifiers(text)
      sources.map { |source| merge_labeled_identifier(source, hints) }
    end

    MONEY_FIELDS = %i[balance credit_limit outstanding_balance monthly_payment principal_amount].freeze

    # The AI sometimes concatenates a formatted amount's digits into one
    # integer ("19.877.599,71" -> 1987759971). When an AI amount is a whole
    # number whose digits match the digits of an amount printed in the
    # statement, replace it with the value parsed from the text.
    def repair_amounts_from_text(sources, text)
      candidates = text.to_s.scan(/\d{1,3}(?:\.\d{3})+(?:,\d+)?/).map do |match|
        { digits: match.scan(/\d/).join, value: parse_amount_text(match) }
      end
      return sources if candidates.empty?

      sources.map do |source|
        MONEY_FIELDS.each do |field|
          value = source[field]
          next unless value.is_a?(Numeric) && value == value.truncate

          match = candidates.find { |candidate| candidate[:digits] == value.to_i.to_s }
          source[field] = BigDecimal(match[:value].to_s) if match
        end
        source
      end
    end

    def labeled_identifiers(text)
      {
        account: labeled_digits(text, ACCOUNT_NUMBER_LABEL, min: 8, max: 20),
        card: labeled_digits(text, CARD_NUMBER_LABEL, min: 4, max: 19),
        loan: labeled_digits(text, LOAN_NUMBER_LABEL, min: 4, max: 20)
      }
    end

    def labeled_digits(text, label, min:, max:)
      combined = Regexp.new("(?:#{label.source})[:.\\s]*#{LABELED_NUMBER.source}", Regexp::IGNORECASE | Regexp::MULTILINE)
      text.to_s.scan(combined).each do |match|
        digits = Array(match).join.scan(/\d/).join
        return digits if digits.length.between?(min, max)
      end
      nil
    end

    def merge_labeled_identifier(source, hints)
      case source[:kind]
      when "account"
        # Only the last four digits are ever stored, matching cards.
        if hints[:account].present?
          last4 = normalize_card(hints[:account])
          source[:identifier] = last4 if last4.present?
          source[:card_last_four] = last4 if last4.present?
        end
      when "credit_card"
        if hints[:card].present?
          last4 = hints[:card][-4..]
          source[:card_last_four] = last4
          source[:identifier] = last4
        end
      else
        source[:card_last_four] = nil
        # Loans store only the last four digits of the contract number, matching
        # accounts and cards. Fill it in from the labeled text only when the AI
        # did not provide one.
        if source[:kind] == "loan" && source[:identifier].blank? && hints[:loan].present?
          source[:identifier] = normalize_card(hints[:loan])
        end
      end
      source
    end

    def digits_only(value)
      value.to_s.scan(/\d/).join.presence
    end

  def normalize_card(value)
    digits = digits_only(value)
    return nil unless digits
    last4 = digits[-4..]
    last4&.length == 4 ? last4 : nil
  end

    # A card number is a long run of digits (>= 12). Used to avoid using a raw
    # card number as the displayed name.
    def card_number?(value)
      digits = value.to_s.gsub(/[\s-]/, "").scan(/\d/).join
      digits.length >= 12
    end

    def normalize_rate_type(value)
      type = value.to_s.downcase.gsub(/\s+/, "_")
      return type if %w[effective_annual nominal_annual monthly].include?(type)

      nil
    end
  end
end

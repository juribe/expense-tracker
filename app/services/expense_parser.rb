# frozen_string_literal: true

require "json"
require "net/http"
require "set"
require "uri"

# Converts natural-language input (text or a voice transcription) into
# structured expense data WITHOUT persisting anything.
#
#   ExpenseParser.call(text: "Me gasté 50 mil en restaurante y 20 mil en parqueadero", user: current_user)
#
# Returns:
#   {
#     engine: "ai" | "heuristic",
#     transcription: "...",
#     expenses: [ { amount:, description:, transaction_date:, category_id:,
#                   category_name:, create_category:, confidence:, low_confidence:,
#                   warnings: } ],
#     errors: ["..."]
#   }
#
# When an OpenAI-compatible API key is configured the text is interpreted by an
# LLM using strict JSON output. Otherwise - or whenever the AI call fails - a
# deterministic rule-based parser handles common Colombian expressions such as
# "50 mil", "50 lucas", "50.000 pesos", "50k" and "medio millón", plus relative
# dates like "hoy", "ayer", "anteayer" and weekdays ("el lunes").
class ExpenseParser
  DEFAULT_CURRENCY = "COP"
  LOW_CONFIDENCE_THRESHOLD = 0.75

  # Spanish keyword groups used to map free text to canonical categories.
  SYNONYM_GROUPS = [
    { canonical: "Restaurants", keywords: %w[restaurant restaurants restaurantes almuerzo comida cena desayuno lunch snack pizza hamburguesa cafe cafeteria bar] },
    { canonical: "Groceries", keywords: %w[groceries grocery mercado supermercado super compras frutas verduras tienda] },
    { canonical: "Parking", keywords: %w[parking parqueadero parqueo estacionamiento] },
    { canonical: "Gasoline", keywords: %w[gasolina gasoline gasolinera combustible nafta] },
    { canonical: "Transportation", keywords: %w[transporte transportation bus taxi uber metro transmilenio pasaje peaje] },
    { canonical: "Entertainment", keywords: %w[entretenimiento entertainment cine pelicula fiesta concierto juegos] },
    { canonical: "Health", keywords: %w[salud health farmacia medicina doctor medico hospital clinica] },
    { canonical: "Education", keywords: %w[educacion education universidad colegio libros matricula curso] },
    { canonical: "Housing", keywords: %w[housing hogar casa arriendo renta alquiler servicios luz agua internet] },
    { canonical: "Pet Care", keywords: %w[pets mascotas mascota perro gato veterinaria veterinario] },
    { canonical: "Clothing", keywords: %w[clothing ropa zapatos camisa vestido] },
    { canonical: "Travel", keywords: %w[travel viaje hotel avion vuelo equipaje] },
    { canonical: "Others", keywords: %w[otros others varios miscelaneo] }
  ].freeze

  NUMBER_WORDS = {
    "un" => 1, "una" => 1, "uno" => 1,
    "dos" => 2, "tres" => 3, "cuatro" => 4, "cinco" => 5, "seis" => 6,
    "siete" => 7, "ocho" => 8, "nueve" => 9, "diez" => 10, "once" => 11,
    "doce" => 12, "trece" => 13, "catorce" => 14, "quince" => 15,
    "veinte" => 20, "treinta" => 30, "cuarenta" => 40, "cincuenta" => 50,
    "sesenta" => 60, "setenta" => 70, "ochenta" => 80, "noventa" => 90,
    "cien" => 100, "ciento" => 100, "doscientos" => 200, "trescientos" => 300,
    "cuatrocientos" => 400, "quinientos" => 500, "seiscientos" => 600,
    "setecientos" => 700, "ochocientos" => 800, "novecientos" => 900
  }.freeze

  WEEKDAYS = {
    "lunes" => 1, "martes" => 2, "miercoles" => 3, "jueves" => 4,
    "viernes" => 5, "sabado" => 6, "domingo" => 0
  }.freeze

  DATE_WORDS = (WEEKDAYS.keys + %w[hoy ayer anteayer el esta este]).to_set.freeze

  FILLER_WORDS = %w[
    me yo mi gaste gasto gastamos gasta pague pagar compre compro
    en de del al la las los un una unos unas que con para por y o
    a tambien solo fueron era son es
  ].to_set.freeze

  class AIError < StandardError; end

  Resolution = Struct.new(:category, :suggested_name, :confidence)

  class << self
    def call(text:, user:, today: Date.current)
      new(text: text, user: user, today: today).call
    end
  end

  def initialize(text:, user:, today:)
    @text = text.to_s.strip
    @user = user
    @today = today
    @categories = Category.all.order(:name).to_a
    @notes = []
  end

  def call
    entries, engine = run_provider
    expenses = entries.filter_map do |entry|
      expense = build_expense(entry)
      if expense.valid?
        expense
      else
        @notes.concat(expense.errors.map { |message| "#{expense.description}: #{message}" })
        nil
      end
    end

    {
      engine: engine,
      transcription: @text,
      expenses: expenses.map { |expense| serialize(expense) },
      errors: @notes.uniq
    }
  end

  private

  # ------------------------------------------------------------------ provider

  def run_provider
    if ai_api_key.present?
      begin
        entries = parse_with_ai
        return [ entries.map { |e| normalize_ai_entry(e) }, "ai" ] if entries.is_a?(Array) && entries.any?

        @notes << "AI returned no usable expenses."
      rescue ExpenseParser::AIError => e
        @notes << "AI parsing failed, used rule-based fallback (#{e.message})."
      end
    end
    [ parse_heuristically, "heuristic" ]
  end

  def ai_api_key
    ENV["OPENAI_API_KEY"].presence
  end

  # Calls an OpenAI-compatible chat completions endpoint with JSON output.
  def parse_with_ai
    uri = URI(ENV.fetch("OPENAI_BASE_URL", "https://api.openai.com/v1/chat/completions"))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 25

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ai_api_key}"
    request.body = {
      model: ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
      temperature: 0,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: ai_system_prompt },
        { role: "user", content: @text }
      ]
    }.to_json

    response = http.request(request)
    raise AIError, "HTTP #{response.code}" unless response.code.to_i == 200

    content = JSON.parse(response.body).dig("choices", 0, "message", "content")
    data = JSON.parse(content)
    entries = data["expenses"]
    raise AIError, "missing 'expenses' array" unless entries.is_a?(Array)

    entries.filter_map do |entry|
      next unless entry.is_a?(Hash)

      entry.symbolize_keys
    end
  rescue JSON::ParserError, TypeError, KeyError => e
    raise AIError, "invalid response (#{e.message})"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise AIError, e.message
  end

  def ai_system_prompt
    categories_list = @categories.map(&:name).join(", ")
    <<~PROMPT
      You extract expense records from natural language (Spanish/Colombian usage).
      Current date: #{@today.iso8601}. Currency: #{DEFAULT_CURRENCY}.
      User's existing categories: [#{categories_list}].
      Rules:
      - One input may contain multiple expenses; return one entry per expense.
      - Interpret Colombian amounts: "50 mil"/"50 lucas"/"50k" = 50000, "50.000 pesos" = 50000, "medio millon" = 500000.
      - Resolve relative dates ("hoy", "ayer", "anteayer", "el lunes") to an ISO date (YYYY-MM-DD).
      - Use one of the user's existing categories when it fits; otherwise set "create_category": true and suggest a short English category name.
      - Include a confidence between 0 and 1.
      Respond with ONLY JSON of the shape:
      {"expenses":[{"amount":50000,"category":"Restaurants","description":"Restaurante","transaction_date":"#{@today.iso8601}","confidence":0.95,"create_category":false}]}
    PROMPT
  end

  # Maps a raw AI hash into the internal entry shape used by build_expense:
  #   { amount:, description:, transaction_date:, category_name:, create_category:, confidence: }
  def normalize_ai_entry(entry)
    entry = entry.symbolize_keys
    {
      amount: entry[:amount],
      description: entry[:description].presence,
      transaction_date: parse_iso_date(entry[:transaction_date]) || @today,
      category_name: entry[:category_name].presence || entry[:category].presence,
      create_category: entry[:create_category],
      confidence: entry[:confidence],
      source_hint: nil
    }
  end

  # ----------------------------------------------------------------- heuristic

  def parse_heuristically
    normalized = normalize_text(@text)
    matches = scan_amounts(normalized)
    return [] if matches.empty?

    matches.each_with_index.filter_map do |match, index|
      previous_end = index.zero? ? 0 : matches[index - 1][:end]
      prefix = normalized[previous_end...match[:start]].to_s
      window_end = index == matches.length - 1 ? normalized.length : matches[index + 1][:start]
      window = normalized[match[:end]...window_end].to_s

      build_heuristic_entry(raw_amount: match[:raw], prefix: prefix, window: window)
    end
  end

  def build_heuristic_entry(raw_amount:, prefix:, window:)
    value, amount_confidence = interpret_amount(raw_amount)
    # The date expression normally precedes its amount ("ayer gasté…"), so
    # the prefix is checked before the following segment.
    date, date_confidence = detect_date(prefix) || detect_date(window) || [ @today, 0.95 ]
    description = clean_description(window).presence || clean_description(prefix).presence

    resolution = resolve_category(description, window)

    warnings = []
    warnings << "We are not sure about this expense amount. Detected: $#{value.to_i}" if amount_confidence < LOW_CONFIDENCE_THRESHOLD
    warnings << "We assumed the date is #{date.iso8601}. Please confirm." if date_confidence < LOW_CONFIDENCE_THRESHOLD
    warnings << "No matching category found. A new \"#{resolution.suggested_name}\" category will be created." if resolution.category.nil?

    confidence = [ amount_confidence, date_confidence, resolution.confidence ].min.round(2)

    ParsedExpense.new(
      amount: BigDecimal(value.to_s),
      description: description.presence || resolution.suggested_name,
      transaction_date: date,
      category_id: resolution.category&.id,
      category_name: resolution.category&.name || resolution.suggested_name,
      create_category: resolution.category.nil?,
      confidence: confidence,
      warnings: warnings
    )
  end

  # ------------------------------------------------------------------- amounts

  def scan_amounts(text)
    results = []
    position = 0
    while (match = AMOUNT_REGEX.match(text, position))
      results << { start: match.begin(0), end: match.end(0), raw: match[:amount].strip }
      position = match.end(0)
    end
    results
  end

  NUMBER_WORD_ALTERNATION = NUMBER_WORDS.keys.sort_by(&:length).reverse.join("|")

  # Matches amounts such as: 50.000 | 50,000 | 1'200.000 (grouped thousands),
  # medio millon, cuarto de millon, "50 mil", "cincuenta mil", "50 lucas",
  # "80k", "500 pesos" and plain integers or decimals.
  AMOUNT_REGEX = /
    (?<amount>
        \d{1,3}(?:['.,]\s?\d{3})+                                     |
        medio\s+millon                                                |
        (?:un\s+)?cuarto\s+de\s+millon                                |
        (?:\d+(?:[.,]\d+)?|(?:#{NUMBER_WORD_ALTERNATION})(?:\s+y\s+(?:#{NUMBER_WORD_ALTERNATION}))*)\s*(?:mil|lucas|luca)\b |
        \d+\s*k\b                                                     |
        \d+(?:[.,]\d+)?\s*(?:pesos|cop)\b                             |
        \d+(?:\.\d{1,2})?
    )
  /x.freeze

  # Returns [BigDecimal value, confidence]
  def interpret_amount(raw)
    text = raw.gsub(/\s+/, " ").strip

    if text.match?(/\A\d{1,3}(?:['.,]\s?\d{3})+\z/)
      return [ text.delete("'.,").to_d, 0.95 ]
    elsif text.match?(/\Amedio\s+millon\z/)
      return [ 500_000, 0.95 ]
    elsif text.match?(/\A(?:un\s+)?cuarto\s+de\s+millon\z/)
      return [ 250_000, 0.9 ]
    elsif (multiplier = text.match(/\A(.+?)\s*(lucas|luca|mil)\z/))
      base, word_confidence = multiplier_base(multiplier[1])
      slang = multiplier[2].match?(/luca/)
      return [ base * 1000, [ word_confidence, slang ? 0.85 : 0.95 ].min ]
    elsif (kilos = text.match(/\A(\d+)\s*k\z/))
      return [ kilos[1].to_i * 1000, 0.85 ]
    elsif (plain = text.match(/\A(\d+)(?:[.,](\d{1,2}))?\s*(pesos|cop)?\z/))
      cents = plain[2]
      value = plain[1].to_d
      value += cents.to_d / 100 if cents
      return [ value, plain[3] ? 0.95 : 0.7 ]
    end

    [ text.scan(/\d+/).first.to_i, 0.5 ]
  end

  # Base for "mil"/"lucas" multipliers: digits ("50"), decimals ("1,5") or
  # number words ("cincuenta").
  def multiplier_base(token)
    token = token.strip
    if token.match?(/\A\d+(?:[.,]\d+)?\z/)
      return [ token.tr(",", ".").to_d, 0.95 ]
    end

    sum = token.split(/\s+y\s*/).sum { |word| NUMBER_WORDS[word].to_i }
    [ sum.to_d, 0.75 ]
  end

  # --------------------------------------------------------------------- dates

  # Returns [Date, confidence] when an explicit date expression is found.
  def detect_date(text)
    if text.match?(/\bhoy\b/)
      [ @today, 0.95 ]
    elsif text.match?(/\banteayer\b/)
      [ @today - 2, 0.85 ]
    elsif text.match?(/\bayer\b/)
      [ @today - 1, 0.95 ]
    else
      detect_weekday_date(text)
    end
  end

  def detect_weekday_date(text)
    match = text.match(/\b(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b/)
    return nil unless match

    target_wday = WEEKDAYS[match[1]]
    days_back = (@today.wday - target_wday - 7) % 7
    days_back = 7 if days_back.zero?
    [ @today - days_back, 0.85 ]
  end

  def parse_iso_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    begin
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end

  # ------------------------------------------------------------------ category

  # Resolves a category for the expense, preferring existing categories.
  def resolve_category(description, context)
    haystack = "#{context} #{description}".squish

    group = best_matching_group(haystack)
    if group
      existing = find_existing_category(group)
      return Resolution.new(existing, nil, 0.95) if existing

      return Resolution.new(nil, group[:canonical], 0.6)
    end

    direct = @categories.find do |category|
      name = normalize_text(category.name)
      description = normalize_text(description.to_s)
      next false if description.blank?

      name == description ||
        (name.length >= 5 && description.length >= 5 && name[0, 5] == description[0, 5])
    end
    return Resolution.new(direct, nil, 0.9) if direct

    fallback = description.presence && titleize_words(clean_description(description))
    Resolution.new(nil, fallback.presence || "Others", 0.4)
  end

  def best_matching_group(haystack)
    best = nil
    best_length = 0
    SYNONYM_GROUPS.each do |group|
      keyword = group[:keywords]
        .select { |word| haystack.match?(keyword_pattern(word)) }
        .max_by(&:length)
      next unless keyword

      if keyword.length > best_length
        best_length = keyword.length
        best = group
      end
    end
    best
  end

  # Tolerates plural/singular variants ("restaurante"/"restaurantes").
  def keyword_pattern(word)
    stem = word.sub(/es\z/, "").sub(/s\z/, "")
    /\b#{Regexp.escape(stem)}(?:e?s)?\b/
  end

  def find_existing_category(group)
    @categories.find { |category| normalize_text(category.name) == normalize_text(group[:canonical]) } ||
      @categories.find do |category|
        name = normalize_text(category.name)
        group[:keywords].any? do |word|
          next false if word.length < 5

          name.include?(word) || name.match?(keyword_pattern(word))
        end
      end
  end

  # -------------------------------------------------------------------- shared

  def serialize(expense)
    {
      amount: expense.amount&.to_f,
      description: expense.description,
      transaction_date: expense.transaction_date&.iso8601,
      category_id: expense.category_id,
      category_name: expense.category_name,
      create_category: expense.create_category || false,
      confidence: expense.confidence,
      low_confidence: expense.low_confidence?,
      warnings: Array(expense.warnings)
    }
  end

  def build_expense(entry)
    return entry if entry.is_a?(ParsedExpense)

    ParsedExpense.new(
      amount: to_numeric(entry[:amount]),
      description: entry[:description].presence&.to_s&.strip,
      transaction_date: entry[:transaction_date].is_a?(Date) ? entry[:transaction_date] : parse_iso_date(entry[:transaction_date]),
      category_id: resolve_existing_category_id(entry),
      category_name: entry[:category_name].presence,
      create_category: entry[:create_category],
      confidence: to_float(entry[:confidence]),
      warnings: Array(entry[:warnings]),
      source_hint: entry[:source_hint]
    )
  end

  def resolve_existing_category_id(entry)
    return nil if entry[:create_category]

    name = normalize_text(entry[:category_name].to_s)
    return nil if name.blank?

    exact = @categories.find { |category| normalize_text(category.name) == name }
    return exact.id if exact

    partial = @categories.find { |category| normalize_text(category.name).include?(name) || name.include?(normalize_text(category.name)) }
    partial&.id
  end

  def to_numeric(value)
    return value if value.is_a?(Numeric)
    return nil if value.blank?

    value.to_s.delete("$ .,").to_d
  rescue ArgumentError, TypeError
    nil
  end

  def to_float(value)
    return nil if value.blank?
    return value if value.is_a?(Numeric)

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  ACCENT_MAP = { "á" => "a", "é" => "e", "í" => "i", "ó" => "o", "ú" => "u", "ü" => "u" }.freeze

  def normalize_text(text)
    text.to_s.downcase.gsub(/[áéíóúü]/, ACCENT_MAP).squish
  end

  def clean_description(text)
    tokens = normalize_text(text).scan(/[a-zñ0-9]+/).reject do |token|
      FILLER_WORDS.include?(token) || DATE_WORDS.include?(token) || token.match?(/\A\d+\z/) || WEEKDAYS.key?(token)
    end
    titleize_words(tokens.join(" ")).truncate(80)
  end

  def titleize_words(text)
    text.to_s.split.map(&:capitalize).join(" ")
  end
end

# frozen_string_literal: true

require "set"

# Converts natural-language input (text or a voice transcription) into
# structured expense data WITHOUT persisting anything.
#
#   ExpenseParser.call(text: "Me gasté 50 mil en restaurante y 20 mil en parqueadero", user: current_user)
#   ExpenseParser.call(text: ocr_text, user: current_user, context: "OCR'd payment receipt; prefer the TOTAL line")
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
# Resolution order: a deterministic parser handles common Colombian
# expressions first ("50 mil", "50 lucas", "50.000 pesos", "50k",
# "medio millón") plus relative dates ("hoy", "ayer", "anteayer", "el lunes").
# When the heuristic pass resolves everything confidently, no AI call happens.
# Otherwise the message goes through Ai::Router (cheap model first, strong
# model on low confidence or failure). If every AI tier fails, the heuristic
# result is returned with a note.
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

  Resolution = Struct.new(:category, :suggested_name, :confidence)

  class << self
    def call(text:, user:, today: Date.current, context: nil, execution: nil)
      new(text: text, user: user, today: today, context: context, execution: execution).call
    end
  end

  def initialize(text:, user:, today:, context: nil, execution: nil)
    @text = text.to_s.strip
    @user = user
    @today = today
    @context = context.to_s.presence
    @execution = execution
    @categories = Category.for_user(user).order(:name).to_a
    @money_source_detector = MoneySources::Detector.new(user: user)
    @notes = []
  end

  def call
    entries, engine, ai_strategy = run_provider
    expenses = entries.filter_map do |entry|
      expense = build_expense(entry)
      assign_money_source(expense)
      apply_matching_rule_category(expense)
      if expense.valid?
        expense
      else
        @notes.concat(expense.errors.map { |message| "#{expense.description}: #{message}" })
        nil
      end
    end

    {
      engine: engine,
      ai_strategy: ai_strategy,
      transcription: @text,
      expenses: expenses.map { |expense| serialize(expense) },
      errors: @notes.uniq
    }
  end

  private

  # ------------------------------------------------------------------ provider

  # Resolution order: deterministic heuristic → AI routing (cheap model first,
  # strong model on low confidence or failure) → heuristic fallback. When the
  # heuristic pass resolves every expense confidently, no AI call happens.
  def run_provider
    heuristic = parse_heuristically

    if force_ai?
      entries, strategy = parse_with_routing
      return [ entries, "ai", strategy ] if entries.present?

      return [ heuristic, "heuristic", nil ]
    end

    if deterministic_confident?(heuristic)
      record_deterministic_resolution(heuristic)
      return [ heuristic, "heuristic", "deterministic" ]
    end

    entries, strategy = parse_with_routing
    return [ entries, "ai", strategy ] if entries.present?

    [ heuristic, "heuristic", nil ]
  end

  def parse_with_routing
    return nil, nil unless ai_configured?

    result = Ai::Router.call(
      task: :expense_extraction,
      input: @text,
      context: { user: @user, today: @today, categories: @categories, context: @context, execution: @execution }
    )
    unless result.ok?
      @notes << "AI parsing failed, used rule-based fallback (#{result.error})."
      return nil, nil
    end

    entries = result.data.map { |entry| normalize_ai_entry(entry) }
    entries.present? ? [ entries, result.strategy ] : [ nil, nil ]
  end

  # Heuristic entries with every confidence component at or above the
  # deterministic threshold are trusted without an AI call.
  def deterministic_confident?(entries)
    return false if entries.empty?

    threshold = Ai.configuration.deterministic_threshold
    entries.all? { |expense| expense.confidence.to_f >= threshold && expense.warnings.blank? }
  end

  def record_deterministic_resolution(entries)
    # Only worth recording when an AI call would otherwise have happened.
    return unless ai_configured?

    Ai::Recorder.write(task: "expense_extraction", user: @user, strategy: "deterministic",
                       provider: nil, status: "ok", escalated: false, error: nil,
                       confidence: entries.map(&:confidence).compact.min,
                       input_tokens: nil, output_tokens: nil, latency_ms: nil)
  end

  def ai_configured?
    return configured_override? if @execution&.override?

    ENV["MISTRAL_API_KEY"].present? || Ai.configuration.cheap_enabled?
  end

  def force_ai?
    @execution&.force_ai? || false
  end

  # An evaluation override is usable when the requested vendor client builds
  # and carries a key/endpoint; e.g. OpenRouter reads OPENROUTER_API_KEY.
  def configured_override?
    provider = Ai::Providers.build(provider: @execution.provider, model: @execution.model)
    provider&.configured?
  rescue ArgumentError
    false
  end

  # Maps a raw AI hash (from the router) into the internal entry shape used
  # by build_expense:
  #   { amount:, description:, transaction_date:, category_name:, create_category:, confidence: }
  def normalize_ai_entry(entry)
    entry = entry.with_indifferent_access
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

  # ----------------------------------------------------------------- category

  # The preview must reflect what will actually be saved: when a transaction
  # rule matches the detected expense, its category replaces the parser's
  # suggestion, so no "new category will be created" warning is shown.
  def apply_matching_rule_category(expense)
    probe = Expense.new(user: @user, description: expense.description.presence,
                        amount: expense.amount, money_source_id: expense.money_source_id)
    rule = TransactionRules::Applicator.new(@user).matching_category_rule(probe)
    return if rule.nil?

    expense.category_id = rule.category_id
    expense.category_name = rule.category.name
    expense.create_category = false
    expense.warnings = expense.warnings.grep_v(/\ANo matching category found/)
  end

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

  # A single mention of an account in the message usually applies to every
  # detected expense (e.g. "gasté 50 mil en almuerzo y 20 mil en parqueadero
  # desde nequi"). If a specific source was already attached, leave it alone.
  def assign_money_source(expense)
    return if expense.money_source_id.present?

    source = @money_source_detector.call(@text)
    return unless source

    expense.money_source_id = source.id
    expense.money_source_name = source.name
  end

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
      warnings: Array(expense.warnings),
      money_source_id: expense.money_source_id,
      money_source_name: expense.money_source_name
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

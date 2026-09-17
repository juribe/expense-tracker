# frozen_string_literal: true

require "set"
require_relative "expense_parser/amount_service"
require_relative "expense_parser/date_service"
require_relative "expense_parser/category_service"
require_relative "expense_parser/text_service"

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
# Pipeline (each step is a clearly separated section below):
#   1. Orchestration     — run the provider, enrich/validate each entry, serialize
#   2. Provider          — deterministic heuristic → AI routing → heuristic fallback
#   3. Heuristic parser  — scan amount expressions and build one entry per match
#   4. Amount reading    — turn raw expressions ("50 mil", "medio millón") into values
#   5. Date reading      — resolve "hoy", "ayer", weekday names into dates
#   6. Category resolution — map free text to the user's categories
#   7. Assembly          — build ParsedExpense, attach money source, apply rules
#   8. Serialization     — present expenses as plain hashes
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

  # Deterministic amount readings confident enough to override an AI value.
  # "20 mil"/"20 lucas"/"850.000" read at >= 0.8; a bare word-number or an
  # unformatted integer stays below and never overrides.
  RECONCILE_CONFIDENCE_THRESHOLD = 0.8

  Resolution = Struct.new(:category, :suggested_name, :confidence)

  # ==========================================================================
  # Public API
  # ==========================================================================

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

  # ==========================================================================
  # 1. ORCHESTRATION — run the provider, then enrich, validate and serialize
  # ==========================================================================

  def call
    entries, engine, ai_strategy = run_provider
    expenses = entries.filter_map { |entry| build_expense_entry(entry) }

    {
      engine: engine,
      ai_strategy: ai_strategy,
      transcription: @text,
      expenses: expenses.map { |expense| serialize(expense) },
      errors: @notes.uniq
    }
  end

  # Per-entry pipeline: assemble → attach money source → apply category rule.
  # Invalid entries are collected as notes and dropped from the result.
  def build_expense_entry(entry)
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

  private

  # ==========================================================================
  # 2. PROVIDER RESOLUTION — deterministic heuristic vs AI routing
  # ==========================================================================

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
    entries = reconcile_amounts(entries)
    entries.present? ? [ entries, result.strategy ] : [ nil, nil ]
  end

  # Maps a raw AI hash (from the router) into the internal entry shape used
  # by build_expense:
  #   { amount:, description:, transaction_date:, category_name:, create_category:, confidence: }
  def normalize_ai_entry(entry)
    entry = entry.with_indifferent_access
    {
      amount: entry[:amount],
      description: entry[:description].presence,
      transaction_date: ExpenseParserServices::DateService.parse_iso_date(entry[:transaction_date]) || @today,
      category_name: entry[:category_name].presence || entry[:category].presence,
      create_category: entry[:create_category],
      confidence: entry[:confidence],
      source_hint: nil
    }
  end

  # The AI occasionally misexpands Colombian amounts ("20 mil" read as
  # 2.000.000). When the message carries exactly one unambiguous amount
  # expression, prefer the deterministic reading (which is how the heuristic
  # parser reports the same text) over the AI value.
  def reconcile_amounts(entries)
    return entries if entries.length != 1

    recovered, confidence = deterministic_amount
    return entries if recovered.nil? || confidence < RECONCILE_CONFIDENCE_THRESHOLD

    entry = entries.first
    entry[:amount] = recovered
    entry[:confidence] = [ entry[:confidence].to_f, confidence ].min
    [ entry ]
  end

  # Deterministic amount recovered from the source text: nil unless exactly
  # one amount expression is present and confidently interpretable.
  def deterministic_amount
    matches = ExpenseParserServices::AmountService.scan_amounts(ExpenseParserServices::TextService.normalize_text(@text))
    uniques = matches.map { |match| match[:raw] }.uniq
    return [ nil, 0.0 ] unless uniques.length == 1

    ExpenseParserServices::AmountService.interpret_amount(uniques.first)
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

  # ==========================================================================
  # 3. HEURISTIC PARSER — deterministic extraction from the text
  # ==========================================================================

  def parse_heuristically
    normalized = ExpenseParserServices::TextService.normalize_text(@text)
    matches = ExpenseParserServices::AmountService.scan_amounts(normalized)
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
    value, amount_confidence = ExpenseParserServices::AmountService.interpret_amount(raw_amount)
    # The date expression normally precedes its amount ("ayer gasté…"), so
    # the prefix is checked before the following segment.
    date, date_confidence = detect_date(prefix) || detect_date(window) || [ @today, 0.95 ]
    description = ExpenseParserServices::TextService.clean_description(window).presence || ExpenseParserServices::TextService.clean_description(prefix).presence

    resolution = ExpenseParserServices::CategoryService.resolve_category(description, window, @categories)

    warnings = []
    warnings << "We are not sure about this expense amount. Detected: $#{value.to_i}" if amount_confidence < LOW_CONFIDENCE_THRESHOLD
    warnings << "We assumed the date is #{date.iso8601}. Please confirm." if date_confidence < LOW_CONFIDENCE_THRESHOLD
    if resolution.category.nil? && resolution.suggested_name.present?
      warnings << "No matching category found. A new \"#{resolution.suggested_name}\" category will be created."
    elsif resolution.category.nil?
      warnings << "We could not determine a category for this expense. You can assign it when you confirm."
    end

    confidence = [ amount_confidence, date_confidence, resolution.confidence ].min.round(2)

    ParsedExpense.new(
      amount: BigDecimal(value.to_s),
      description: description.presence || resolution.suggested_name,
      transaction_date: date,
      category_id: resolution.category&.id,
      category_name: resolution.category&.name || resolution.suggested_name,
      create_category: resolution.category.nil? && resolution.suggested_name.present?,
      confidence: confidence,
      warnings: warnings
    )
  end

  # ==========================================================================
  # 4. DATE READING — relative words and weekday names → dates
  # ==========================================================================

  # Returns [Date, confidence] when an explicit date expression is found.
  def detect_date(text)
    ExpenseParserServices::DateService.detect_date(text, today: @today)
  end

  # ==========================================================================
  # 7. ASSEMBLY — entries → ParsedExpense, enriched and validated
  # ==========================================================================
  def build_expense(entry)
    return entry if entry.is_a?(ParsedExpense)

    ParsedExpense.new(
      amount: to_numeric(entry[:amount]),
      description: entry[:description].presence&.to_s&.strip,
      transaction_date: entry[:transaction_date].is_a?(Date) ? entry[:transaction_date] : ExpenseParserServices::DateService.parse_iso_date(entry[:transaction_date]),
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

    name = ExpenseParserServices::TextService.normalize_text(entry[:category_name].to_s)
    return nil if name.blank?

    exact = @categories.find { |category| ExpenseParserServices::TextService.normalize_text(category.name) == name }
    return exact.id if exact

    partial = @categories.find { |category| ExpenseParserServices::TextService.normalize_text(category.name).include?(name) || name.include?(ExpenseParserServices::TextService.normalize_text(category.name)) }
    partial&.id
  end

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
    expense.warnings = expense.warnings.grep_v(/\A(?:No matching category found|We could not determine a category)/)
  end

  # ==========================================================================
  # 8. SERIALIZATION & SHARED HELPERS
  # ==========================================================================

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
end

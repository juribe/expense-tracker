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
    provider = Provider.new(text: @text, user: @user, today: @today, categories: @categories, context: @context, execution: @execution, notes: @notes)
    entries, engine, ai_strategy = provider.run

    assembler = ExpenseParser::Assembler.new(text: @text, user: @user, categories: @categories, notes: @notes, money_source_detector: @money_source_detector)
    expenses = entries.filter_map { |entry| assembler.build(entry) }

    {
      engine: engine,
      ai_strategy: ai_strategy,
      transcription: @text,
      expenses: Serializer.call(expenses),
      errors: @notes.uniq
    }
  end
end

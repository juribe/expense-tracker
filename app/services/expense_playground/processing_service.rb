# frozen_string_literal: true

module ExpensePlayground
  # Orchestrates the full ingestion pipeline for any normalized Input:
  #
  #   Input → Speech-to-Text (audio only) → OCR (local Tesseract; vision model
  #           as fallback when applicable) → AI Extraction → Normalization →
  #   Validation → ExpenseCandidate
  #
  # Audio is just another way of producing text: its transcript reuses the
  # same ExpenseParser as typed text, and there is no separate audio
  # extraction path.
  #
  # It NEVER persists anything. The Playground (and future channels such as
  # WhatsApp/voice/email) receives a Result with the candidate plus every
  # pipeline stage recorded for debugging.
  #
  #   result = ExpensePlayground::ProcessingService.call(user: user, input: input)
  #   result.ok?             # => true
  #   result.candidate       # => ExpenseCandidate
  #   result.steps[:stt]     # => { applicable: false } | { provider: ..., text: ... }
  #   result.steps[:ocr]     # => { applicable: false } | { applicable: true, text: ..., engine: ... }
  class ProcessingService
    class << self
      def call(user:, input:, execution: nil)
        new(user: user, input: input, execution: execution).call
      end
    end

    Result = Struct.new(:candidate, :steps, :errors, :warnings, :duration_ms, :engine, keyword_init: true) do
      def ok?
        candidate.present? && candidate.valid? && errors.empty?
      end
    end

    # Digital subscriptions/services (any case/format) that must never resolve
    # to "Servicios públicos": those are actual utilities (water, electricity,
    # gas, internet, phone). Kept as a deterministic guard so a small model
    # cannot hard-push a wrong utilities label that would survive reconfirm.
    NON_UTILITY_DIGITAL_TERMS = %w[
      netflix spotify disney canva chatgpt openai microsoft adobe icloud
      dropbox google-one prime hbo max paramount crunchyroll youtube
    ].freeze

    # Streaming services classify as "Entretenimiento" (they are not utilities).
    STREAMING_TERMS = %w[netflix spotify disney hbo max paramount crunchyroll youtube].freeze

    # Parking-fee keywords that deterministically classify as "Transporte" when
    # the user has that category (mirrors ClosestResolver::PARKING_TERMS).
    PARKING_TERMS = %w[parking parqueadero parqueo estacionamiento].freeze

    # Words stripped when building a suggested NEW category name from an
    # unmatched activity, so the suggestion reads like a name, not a sentence.
    SUGGESTION_STOP_WORDS = %w[
      pague pago gasto gaste pagar compre compro gastamos solo en de del al la
      las los un una unos unas que con para por y o a tambien fueron me mi era
      son es mil lucas pesos
    ].freeze

    def initialize(user:, input:, execution: nil)
      @user = user
      @input = input
      @execution = execution
      @steps = {}
      @errors = []
      @warnings = []
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      record_input
      unless @input.valid?
        @errors.concat(@input.errors)
        return build_result(nil, nil, started)
      end

      ocr = run_ocr
      transcript = run_speech_to_text
      extracted, engine = run_extraction(ocr, transcript)
      return build_result(nil, engine, started) if extracted.nil?

      candidate = normalize(extracted)
      validate(candidate)

      build_result(candidate, engine, started)
    end

    private

    # ----------------------------------------------------------------- stages

    def record_input
      @steps[:input] = {
        type: @input.type,
        text: @input.payload[:text],
        image: @input.image? || @input.text_image? ? "(image attached, #{Inputs::Image.mime_type(@input.image_data)})" : nil,
        audio: @input.audio? ? "(audio attached, #{Inputs::Audio.extension(@input.audio_data, @input.filename)}, #{@input.filename})" : nil
      }
    end

    # Speech-to-Text is only applicable when audio is part of the input. It
    # runs LOCALLY (provider from configuration, Whisper by default) and the
    # audio never leaves the machine. Failures become friendly pipeline
    # errors; they never abort with a provider stack trace.
    def run_speech_to_text
      unless @input.audio?
        @steps[:stt] = { applicable: false }
        return nil
      end

      result = SpeechToText.transcribe(audio_data: @input.audio_data, filename: @input.filename)
      @steps[:stt] = {
        applicable: true,
        provider: result.provider,
        model: result.model,
        language: result.language,
        language_probability: result.language_probability,
        duration: result.duration,
        text: result.text
      }
      if result.empty_transcript?
        @errors << "Speech-to-text produced an empty transcript. The audio may be silent or too short."
        return nil
      end
      result.text
    rescue SpeechToText::Error => e
      @steps[:stt] = { applicable: true, provider: SpeechToText.provider_name, error: e.message }
      @errors << e.message
      nil
    end

    def run_extraction(ocr_text, transcript)
      if @input.audio?
        extract_from_transcript(transcript)
      elsif @input.image? || @input.text_image?
        ocr_text.present? ? extract_from_ocr_text(ocr_text) : extract_from_image
      else
        extract_from_text
      end
    end

    # Voice-note pipeline: the transcript is parsed together with the user's
    # optional note (explicit intent such as "pagado con nequi") through the
    # same ExpenseParser used for plain text inputs.
    def extract_from_transcript(transcript)
      if transcript.blank?
        @errors << "Could not extract an expense because no transcript was generated." if @errors.empty?
        return [ nil, nil ]
      end

      parse_into_entry(
        [ @input.text, transcript ].reject(&:blank?).join("\n"),
        context: "This text was transcribed from a voice note by local speech-to-text. " \
                 "Extract the expense exactly as spoken."
      )
    end

    # OCR is only applicable when an image is part of the input. It runs
    # LOCALLY with Tesseract (the image never leaves the machine); when
    # Tesseract is unavailable or reads nothing, the vision model becomes
    # the fallback and performs OCR + extraction in one call.
    def run_ocr
      unless @input.image? || @input.text_image?
        @steps[:ocr] = { applicable: false }
        return nil
      end

      text = Ocr::LocalReader.call(image_data: @input.image_data)
      if text.present?
        @steps[:ocr] = { applicable: true, engine: "tesseract", text: text }
        text
      else
        @steps[:ocr] = { applicable: true, pending: true }
        nil
      end
    end

    def extract_from_text
      parse_into_entry(@input.text)
    end

    # Receipt pipeline: parse the OCR text together with the user's note
    # (which carries explicit intent such as "pagué con nequi") through the
    # same ExpenseParser used for plain text inputs. Receipt context helps
    # the AI prefer the TOTAL line over individual item amounts.
    def extract_from_ocr_text(ocr_text)
      parse_into_entry(
        [ @input.payload[:text], ocr_text ].reject(&:blank?).join("\n"),
        context: "This text was OCR'd locally from a payment receipt. When several amounts " \
                 "appear (items, subtotal, total), extract ONE expense using the TOTAL amount."
      )
    end

    def parse_into_entry(text, context: nil)
      result = ExpenseParser.call(text: text, user: @user, context: context, execution: @execution)
      entry = result[:expenses].first
      @warnings.concat(Array(result[:errors]))
      if entry.nil?
        reason = @warnings.grep(/amount/i).first.presence || "no expense could be detected in the text."
        @errors << "Could not extract an expense from this input. Reason: #{reason}"
        return [ nil, result[:engine] ]
      end

      entry = entry.merge!(merchant: nil, currency: ExpenseCandidate::DEFAULT_CURRENCY)
      @warnings.concat(Array(entry[:warnings]))

      @steps[:extraction] = {
        engine: result[:engine],
        ai_strategy: result[:ai_strategy],
        raw: result[:expenses],
        detected_count: result[:expenses].length
      }
      [ entry, result[:engine] ]
    end

    def extract_from_image
      result = Ai::ImageExpenseExtractor.call(
        image_data: @input.image_data,
        context_text: @input.payload[:text]
      )

      unless result[:ok?]
        @errors << "Expense extraction failed. The extraction service returned an invalid response. (#{result[:error]})"
        @steps[:extraction] = { engine: "vision", raw: nil, errors: [ result[:error] ] }
        return [ nil, "vision" ]
      end

      ocr_text = result.dig(:data, :ocr_text)
      entries = result.dig(:data, :expenses)
      @steps[:ocr] = { applicable: true, engine: "mistral-vision", text: ocr_text }
      @steps[:extraction] = { engine: "vision", raw: result.dig(:data, :expenses), detected_count: entries.length }

      if entries.empty?
        @errors << "Could not extract an expense from this input. Reason: no expense could be detected in the image."
        return [ nil, "vision" ]
      end

      entry = entries.first
      assign_money_source_from_context(entry, ocr_text)
      [ entry, "vision" ]
    end

    # The vision extractor returns no money source, so it is detected from
    # the user's note first (explicit intent), then from the receipt's OCR
    # text (e.g. a "Nequi" payment line). Nothing is forced when neither
    # mentions a source.
    def assign_money_source_from_context(entry, ocr_text)
      return if entry.nil? || entry[:money_source_id].present?

      detector = MoneySources::Detector.new(user: @user)
      source = detector.call(@input.payload[:text]) || detector.call(ocr_text)
      return unless source

      entry[:money_source_id] = source.id
      entry[:money_source_name] = source.name
    end

    # Maps the extracted entry into the canonical ExpenseCandidate structure,
    # resolving the category against the user's real categories.
    def normalize(entry)
      category = resolve_category(entry[:category_name], entry[:category_id], activity: entry[:description].presence || entry[:merchant])
      extracted_name = @rejected_category_name ? nil : entry[:category_name].presence
      candidate = ExpenseCandidate.new(
        amount: entry[:amount],
        currency: entry[:currency].presence || ExpenseCandidate::DEFAULT_CURRENCY,
        category_id: category&.id,
        category_name: category&.name || extracted_name,
        description: entry[:description].presence || entry[:merchant].presence,
        merchant: entry[:merchant],
        date: parse_date(entry[:transaction_date]),
        source: "playground",
        confidence: entry[:confidence],
        money_source_id: entry[:money_source_id].presence&.to_i,
        money_source_name: entry[:money_source_name].presence
      )
      if category.nil?
        if candidate.category_name.present?
          @warnings << "We could not match the category \"#{candidate.category_name}\". You can create it or pick an existing one when you confirm."
        elsif (suggested = suggest_category_name(entry[:description].presence || entry[:merchant].presence))
          candidate.category_name = suggested
          candidate.suggested_category_name = suggested
          @warnings << "No matching category found. Suggesting the new category \"#{suggested}\"; confirm to create it or pick an existing one."
        elsif @warnings.grep(/category for this expense/i).empty?
          @warnings << "We could not determine a category for this expense. You can assign it when you confirm."
        end
      end

      @steps[:normalization] = {
        amount: candidate.amount,
        currency: candidate.currency,
        category_id: candidate.category_id,
        category_name: candidate.category_name,
        date: candidate.date&.iso8601,
        money_source_id: candidate.money_source_id,
        money_source_name: entry[:money_source_name],
        matching: if @category_resolution&.matched?
                    {
                      input: entry[:category_name],
                      matched_by: @category_resolution.matched_by,
                      mapped_to: candidate.category_name,
                      similarity: @category_resolution.similarity
                    }
                  end,
        warnings: @warnings
      }
      candidate
    end

    def validate(candidate)
      candidate.valid?
      @steps[:validation] = {
        valid: candidate.valid?,
        checks: candidate.checks,
        errors: candidate.errors
      }
    end

    # -------------------------------------------------------------- categories

    # Category resolution is centralized in Categories::ClosestResolver:
    # exact normalized name, learned activity mappings (ActivityClassification),
    # English -> Spanish aliases and a similarity fold, so a category name that
    # is "very close" to an existing one never creates a near-duplicate. There
    # are no unconditional rules and an absent category stays unassigned.
    # ProcessingService NEVER persists, so similarity folds are resolved but
    # not recorded as knowledge here.
    #
    # Two deterministic business guards run AFTER resolution: parking text
    # always classifies as "Transporte" when the user has it, and a digital
    # subscription (Netflix, Canva, Microsoft 365, ...) is never "Servicios
    # públicos" — it stays unassigned so a suggestion is built instead. These
    # exist so small models cannot hard-push a wrong label that would persist.
    def resolve_category(category_name, category_id, activity: nil)
      categories = Category.for_user(@user)
      @category_resolution = nil
      @rejected_category_name = false
      resolved =
        if category_id.present?
          categories.find_by(id: category_id)
        elsif category_name.present? || activity.present?
          # An absent extracted name stays unassigned unless a deterministic rule
          # or the user's stored knowledge classifies the activity. ClosestResolver
          # applies NO unconditional rules; user knowledge wins when present.
          @category_resolution = Categories::ClosestResolver.call(
            user: @user,
            name: category_name.to_s,
            activity: activity,
            record: false
          )
          @category_resolution.category
        end

      apply_business_guards(resolved, category_name, activity, categories)
    end

    # Enforces the deterministic business rules after any resolution (AI id,
    # ClosestResolver, or none) so a wrong label can never slip through. The
    # raw user text is included so the guards see "Microsoft 365"/"parqueadero"
    # even when the model slimmed the description down.
    def apply_business_guards(resolved, category_name, activity, categories)
      text = [ category_name, activity, @input&.payload&.dig(:text) ].compact.join(" ").to_s.downcase
      return resolved if text.blank?

      transporte = categories.find { |category| ActivityClassification.normalize_name(category.name) == "transporte" }
      if transporte && PARKING_TERMS.any? { |term| text.include?(term) }
        @category_resolution = Categories::ClosestResolver::Result.new(category: transporte, matched_by: :parking, similarity: 1.0)
        return transporte
      end

      utilities = categories.find { |category| ActivityClassification.normalize_name(category.name) == "servicios publicos" }
      if utilities && resolved&.id == utilities.id &&
         NON_UTILITY_DIGITAL_TERMS.any? { |term| text.include?(term) }
        @rejected_category_name = true
        @category_resolution = nil
        return nil
      end

      resolved
    end

    def parse_date(value)
      return Date.current if value.blank?

      begin
        Date.iso8601(value.to_s)
      rescue ArgumentError, Date::Error, TypeError
        Date.parse(value.to_s)
      end
    rescue ArgumentError, Date::Error, TypeError
      nil
    end

    # Builds a short, name-like NEW category from an unmatched activity so a
    # blank category never stays empty:
    #   - streaming services (Netflix, Spotify, ...) suggest "Entretenimiento"
    #   - other digital SaaS (Canva, Microsoft 365, ChatGPT, ...) suggest a new
    #     "Suscripciones" category
    #   - anything else falls back to the cleaned, title-cased activity
    # Returns nil only when nothing scannable remains.
    def suggest_category_name(text)
      return nil if text.blank?

      normalized = ActivityClassification.normalize_name(text).to_s
      return "Entretenimiento" if STREAMING_TERMS.any? { |term| normalized.include?(term) }
      if (NON_UTILITY_DIGITAL_TERMS - STREAMING_TERMS).any? { |term| normalized.include?(term) }
        return "Suscripciones"
      end

      tokens = normalized.split.reject do |token|
        SUGGESTION_STOP_WORDS.include?(token) || token.match?(/\A\d+\z/)
      end
      title = tokens.join(" ")
      return nil if title.blank?

      title.split.map(&:capitalize).join(" ").truncate(40)
    end

    # ------------------------------------------------------------------ result

    def build_result(candidate, engine, started)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      Result.new(
        candidate: candidate,
        steps: @steps,
        errors: @errors.dup,
        warnings: @warnings.dup,
        duration_ms: duration_ms,
        engine: engine
      )
    end
  end
end

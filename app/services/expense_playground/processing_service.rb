# frozen_string_literal: true

module ExpensePlayground
  # Orchestrates the full ingestion pipeline for any normalized Input:
  #
  #   Input → OCR (local Tesseract; vision model as fallback when
  #           applicable) → AI Extraction → Normalization → Validation →
  #   ExpenseCandidate
  #
  # It NEVER persists anything. The Playground (and future channels such as
  # WhatsApp/voice/email) receives a Result with the candidate plus every
  # pipeline stage recorded for debugging.
  #
  #   result = ExpensePlayground::ProcessingService.call(user: user, input: input)
  #   result.ok?           # => true
  #   result.candidate     # => ExpenseCandidate
  #   result.steps[:ocr]   # => { applicable: false } | { applicable: true, text: ..., engine: ... }
  class ProcessingService
    class << self
      def call(user:, input:)
        new(user: user, input: input).call
      end
    end

    Result = Struct.new(:candidate, :steps, :errors, :warnings, :duration_ms, :engine, keyword_init: true) do
      def ok?
        candidate.present? && candidate.valid? && errors.empty?
      end
    end

    def initialize(user:, input:)
      @user = user
      @input = input
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
      extracted, engine = run_extraction(ocr)
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
        text: @input.text,
        image: @input.image? ? "(image attached, #{@input.image_mime_type})" : nil
      }
    end

    # OCR is only applicable when an image is part of the input. It runs
    # LOCALLY with Tesseract (the image never leaves the machine); when
    # Tesseract is unavailable or reads nothing, the vision model becomes
    # the fallback and performs OCR + extraction in one call.
    def run_ocr
      unless @input.image?
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

    def run_extraction(ocr_text)
      if @input.image?
        ocr_text.present? ? extract_from_ocr_text(ocr_text) : extract_from_image
      else
        extract_from_text
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
        [ @input.text, ocr_text ].reject(&:blank?).join("\n"),
        context: "This text was OCR'd locally from a payment receipt. When several amounts " \
                 "appear (items, subtotal, total), extract ONE expense using the TOTAL amount."
      )
    end

    def parse_into_entry(text, context: nil)
      result = ExpenseParser.call(text: text, user: @user, context: context)
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
        raw: result[:expenses],
        detected_count: result[:expenses].length
      }
      [ entry, result[:engine] ]
    end

    def extract_from_image
      result = Ai::ImageExpenseExtractor.call(
        image_data: @input.image_data,
        context_text: @input.text
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
      source = detector.call(@input.text) || detector.call(ocr_text)
      return unless source

      entry[:money_source_id] = source.id
      entry[:money_source_name] = source.name
    end

    # Maps the extracted entry into the canonical ExpenseCandidate structure,
    # resolving the category against the user's real categories.
    def normalize(entry)
      category = resolve_category(entry[:category_name], entry[:category_id])
      candidate = ExpenseCandidate.new(
        amount: entry[:amount],
        currency: entry[:currency].presence || ExpenseCandidate::DEFAULT_CURRENCY,
        category_id: category&.id,
        category_name: category&.name || entry[:category_name].presence,
        description: entry[:description].presence || entry[:merchant].presence,
        merchant: entry[:merchant],
        date: parse_date(entry[:transaction_date]),
        source: "playground",
        confidence: entry[:confidence],
        money_source_id: entry[:money_source_id].presence&.to_i,
        money_source_name: entry[:money_source_name].presence
      )
      if category.nil? && @warnings.grep(/No matching category/).empty?
        @warnings << "No matching category found. A new \"#{candidate.category_name}\" category will be created."
      end

      @steps[:normalization] = {
        amount: candidate.amount,
        currency: candidate.currency,
        category_id: candidate.category_id,
        category_name: candidate.category_name,
        date: candidate.date&.iso8601,
        money_source_id: candidate.money_source_id,
        money_source_name: entry[:money_source_name],
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

    def resolve_category(category_name, category_id)
      return Category.for_user(@user).find_by(id: category_id) if category_id.present?

      name = normalize_name(category_name)
      return nil if name.blank?

      Category.for_user(@user).find { |category| normalize_name(category.name) == name }
    end

    def normalize_name(text)
      text.to_s.downcase.tr("áéíóúü", "aeiouu").squish
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

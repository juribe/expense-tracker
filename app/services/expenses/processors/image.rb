# frozen_string_literal: true

module Expenses
  module Processors
    # Image channel processor, serving both "image" and "text_image" inputs
    # (the only difference is whether the user's optional note is present).
    #
    # Two paths:
    #   1. local OCR (Tesseract) reads text -> the note + OCR text go through
    #      the Text processor (receipt context).
    #   2. Tesseract reads nothing -> a vision model performs OCR + extraction
    #      in one call; the resulting entry is normalized by the Text processor
    #      so every channel ends up with the same candidate mapping.
    class Image < Base
      RECEIPT_CONTEXT = "This text was OCR'd locally from a payment receipt. When several amounts " \
                        "appear (items, subtotal, total), extract ONE expense using the TOTAL amount."

      # Returns [candidate, engine]; candidate is nil when OCR/extraction
      # failed.
      def call
        ocr_text = run_ocr
        if ocr_text.present?
          text_processor.call(
            [ note, ocr_text ].reject(&:blank?).join("\n"),
            context: RECEIPT_CONTEXT
          )
        else
          entry, engine = extract_from_image
          return [ nil, engine ] if entry.nil?

          candidate = build_vision_candidate(entry)
          text_processor.validate(candidate)
          [ [ candidate ], engine ]
        end
      end

    private

    # Maps a vision-extracted entry into the shared ExpenseCandidate shape.
    # Category resolution goes through Categories::HeuristicResolver (aliases,
    # learned activity mappings, parking/housing guards) and unmatched names
    # are kept or replaced by a cleaned suggestion, mirroring the preview
    # behavior of every other channel.
    def build_vision_candidate(entry)
      activity = entry[:description].presence || entry[:merchant].presence
      resolver = Categories::HeuristicResolver.new(
        user: @user,
        name: entry[:category_name].presence,
        activity: activity
      )
      category = resolver.resolve_category(
        entry[:category_name].presence,
        entry[:category_id].presence&.to_i,
        activity: activity
      )
      extracted_name = resolver.rejected_category_name ? nil : entry[:category_name].presence

      warnings = []
      if category.nil?
        if extracted_name.present?
          warnings << "We could not match the category \"#{extracted_name}\". You can create it or pick an existing one when you confirm."
        elsif (suggested = resolver.suggest_category_name(activity))
          warnings << "No matching category found. Suggesting the new category \"#{suggested}\"; confirm to create it or pick an existing one."
        else
          warnings << "We could not determine a category for this expense. You can assign it when you confirm."
        end
      end
      suggested_name = category ? nil : (suggested if extracted_name.blank?)
      @recording&.add_warnings(warnings)

      ExpenseCandidate.new(
        amount: entry[:amount],
        currency: entry[:currency].presence || ExpenseCandidate::DEFAULT_CURRENCY,
        category_id: category&.id,
        category_name: category&.name || suggested_name.presence || extracted_name,
        description: entry[:description].presence || entry[:merchant].presence,
        merchant: entry[:merchant],
        date: ExpenseResolver::Dates::Service.parse_iso_date(entry[:transaction_date]),
        source: "playground",
        classification_source: "vision",
        suggested_category_name: suggested_name,
        confidence: entry[:confidence],
        money_source_id: entry[:money_source_id].presence&.to_i,
        money_source_name: entry[:money_source_name].presence
      )
    end

    # OCR is only applicable when an image is part of the input. It runs
      # LOCALLY with Tesseract (the image never leaves the machine); when
      # Tesseract is unavailable or reads nothing, the vision model becomes
      # the fallback and performs OCR + extraction in one call.
      def run_ocr
        text = Ocr::LocalReader.call(image_data: @input.image_data)
        if text.present?
          @recording&.add_step(:ocr, { applicable: true, engine: "tesseract", text: text })
          text
        else
          @recording&.add_step(:ocr, { applicable: true, pending: true })
          nil
        end
      end

      def extract_from_image
        result = Ai::ImageExpenseExtractor.call(
          image_data: @input.image_data,
          context_text: note
        )

        unless result[:ok?]
          @recording&.add_errors([ "Expense extraction failed. The extraction service returned an invalid response. (#{result[:error]})" ])
          @recording&.add_step(:extraction, { engine: "vision", raw: nil, errors: [ result[:error] ] })
          return [ nil, "vision" ]
        end

        ocr_text = result.dig(:data, :ocr_text)
        entries = result.dig(:data, :expenses)
        @recording&.add_step(:ocr, { applicable: true, engine: "mistral-vision", text: ocr_text })
        @recording&.add_step(:extraction, { engine: "vision", raw: result.dig(:data, :expenses), detected_count: entries.length })

        if entries.empty?
          @recording&.add_errors([ "Could not extract an expense from this input. Reason: no expense could be detected in the image." ])
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
        source = detector.call(note) || detector.call(ocr_text)
        return unless source

        entry[:money_source_id] = source.id
        entry[:money_source_name] = source.name
      end
    end
  end
end

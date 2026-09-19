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

          candidate = text_processor.normalize(entry)
          text_processor.validate(candidate)
          [ candidate, engine ]
        end
      end

      private

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

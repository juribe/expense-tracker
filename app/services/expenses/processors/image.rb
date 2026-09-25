# frozen_string_literal: true

module Expenses
  module Processors
    # Image channel processor, serving both "image" and "text_image" inputs
    # (the only difference is whether the user's optional note is present).
    #
    # It only knows the two ways an image input can be handled:
    #   1. local OCR (Tesseract) reads text -> the note + OCR text go through
    #      the Text processor (receipt context).
    #   2. Tesseract reads nothing -> the vision way (VisionExtraction) calls
    #      a vision model for OCR + extraction and returns a normalized
    #      ExpenseCandidate built through CandidateDetector, so every channel
    #      ends up with the same candidate mapping and category decision.
    class Image < Base
      RECEIPT_CONTEXT = "Este texto fue obtenido mediante OCR local de un comprobante de pago. " \
                  "Cuando aparezcan varios valores (productos, subtotal, total), " \
                  "extrae UN solo gasto usando el valor TOTAL."

      # Returns [candidate, engine]; candidate is nil when OCR/extraction
      # failed.
      def call
        ocr_text = force_vision? ? nil : run_ocr
        if ocr_text.present?
          return text_processor.call(
            combined_text(ocr_text),
            context: RECEIPT_CONTEXT
          )
        end

        vision = VisionExtraction.call(user: @user, input: @input, note: note, recording: @recording)
        return [ nil, vision.engine ] unless vision.ok?

        [ [ vision.candidate ], vision.engine ]
      end

      private

      # The note carries explicit intent about the image ("pagado con nequi"),
      # so it is labeled for the parser and the prompt record.
      def combined_text(ocr_text)
        note_part = note.present? ? "comentario usuario acerca de la imagen: #{note}" : nil
        [ note_part, ocr_text ].reject(&:blank?).join("\n")
      end

      # Debug escape hatch to exercise the vision path with images Tesseract
      # can read: EXPENSES_FORCE_VISION=1 skips local OCR entirely.
      def force_vision?
        ENV["EXPENSES_FORCE_VISION"].present?
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
    end
  end
end

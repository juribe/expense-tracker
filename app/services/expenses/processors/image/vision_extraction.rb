# frozen_string_literal: true

class Expenses::Processors::Image
  # The "vision way" of the Image processor, as one step: calls the strong-tier
  # vision extractor (OCR + extraction in one call), records the pipeline
  # steps and friendly errors, picks the first detected entry and normalizes
  # it into an ExpenseCandidate via VisionCandidateBuilder. The processor only
  # chooses between this and the Text processor path.
  class VisionExtraction
    Result = Struct.new(:ok?, :candidate, :engine, keyword_init: true)

    def self.call(user:, input:, note:, recording: nil)
      new(user: user, input: input, note: note, recording: recording).call
    end

    def initialize(user:, input:, note:, recording: nil)
      @user = user
      @input = input
      @note = note
      @recording = recording
    end

    def call
      result = Ai::ImageExpenseExtractor.call(
        image_data: @input.image_data,
        context_text: @note
      )

      unless result[:ok?]
        @recording&.add_errors([ "Expense extraction failed. The extraction service returned an invalid response. (#{result[:error]})" ])
        @recording&.add_step(:extraction, { engine: "vision", raw: nil, errors: [ result[:error] ] })
        return Result.new(ok?: false, candidate: nil, engine: "vision")
      end

      ocr_text = result.dig(:data, :ocr_text)
      entries = result.dig(:data, :expenses)
      @recording&.add_step(:ocr, { applicable: true, engine: "mistral-vision", text: ocr_text })
      @recording&.add_step(:extraction, { engine: "vision", raw: result.dig(:data, :expenses), detected_count: entries.length })

      if entries.empty?
        @recording&.add_errors([ "Could not extract an expense from this input. Reason: no expense could be detected in the image." ])
        return Result.new(ok?: false, candidate: nil, engine: "vision")
      end

      candidate = VisionCandidateBuilder.call(user: @user, note: @note, entry: entries.first.merge(ocr_text: ocr_text), recording: @recording)
      Result.new(ok?: true, candidate: candidate, engine: "vision")
    end
  end
end

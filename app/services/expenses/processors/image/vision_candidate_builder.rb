# frozen_string_literal: true

class Expenses::Processors::Image
  # Maps a vision-extracted entry into the shared ParsedExpense shape and
  # normalizes it through CandidateDetector, the same converter used by the
  # text pipeline (category decision included, via Categories::Decision).
  class VisionCandidateBuilder
    def self.call(user:, note:, entry:, recording: nil)
      new(user: user, note: note, entry: entry, recording: recording).call
    end

    def initialize(user:, note:, entry:, recording: nil)
      @user = user
      @note = note
      @entry = entry
      @recording = recording
    end

    def call
      ExpenseResolver::CandidateDetector.call(
        expense: parsed_entry,
        user: @user,
        categories: categories,
        money_source_detector: money_source_detector,
        classification_source: "vision",
        recording: @recording
      )
    end

    private

    # original_text is intentionally left nil so the heuristic amount/date
    # re-scan does not override the vision values.
    def parsed_entry
      Ai::Tasks::ParsedExpense.new(
        amount: @entry[:amount],
        currency: @entry[:currency],
        merchant: @entry[:merchant],
        description: @entry[:description].presence || @entry[:merchant].presence,
        category: @entry[:category_name],
        date: ExpenseResolver::Dates::Service.parse_iso_date(@entry[:transaction_date]),
        confidence: @entry[:confidence],
        money_source_id: money_source&.id,
        money_source_name: money_source&.name
      )
    end

    # The vision extractor returns no money source, so it is detected from
    # the user's note first (explicit intent), then from the receipt's OCR
    # text (e.g. a "Nequi" payment line). Nothing is forced when neither
    # mentions a source.
    def money_source
      @money_source ||= money_source_detector.call(@note) || money_source_detector.call(@entry[:ocr_text])
    end

    def money_source_detector
      @money_source_detector ||= MoneySources::Detector.new(user: @user)
    end

    def categories
      Category.for_user(@user).expenses.order(:name).to_a
    end
  end
end

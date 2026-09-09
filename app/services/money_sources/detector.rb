# frozen_string_literal: true

module MoneySources
  # Finds the user's active MoneySource mentioned in a piece of free text by
  # scanning it against each source's name, bank and recognition keyword
  # identifiers. Returns the first matching source, or nil when nothing
  # clearly matches.
  #
  #   MoneySources::Detector.call(user: user, text: "gasté 50 mil desde nequi")
  #
  # Used by ExpenseParser (text/voice input) and the playground pipeline
  # (image/OCR input), so all channels detect sources the same way.
  class Detector
    ACCENT_MAP = { "á" => "a", "é" => "e", "í" => "i", "ó" => "o", "ú" => "u", "ü" => "u" }.freeze

    def self.call(user:, text:)
      new(user: user).call(text)
    end

    def initialize(user:)
      @sources = MoneySource.active.where(user: user)
                            .includes(recognition: :recognition_identifiers).to_a
    end

    def call(text)
      return nil if text.blank?

      clean = normalize_text(text)
      @sources.find { |source| matches?(source, clean) }
    end

    private

    def matches?(source, clean)
      values = [ source.name, source.bank ]
      values.concat(source.recognition_identifiers.select(&:keyword?).map(&:value))
      values.compact.map { |value| normalize_text(value) }.any? do |value|
        next false if value.blank?

        clean.match?(/\b#{Regexp.escape(value)}\b/)
      end
    end

    def normalize_text(text)
      text.to_s.downcase.gsub(/[áéíóúü]/, ACCENT_MAP).squish
    end
  end
end

# frozen_string_literal: true

module MoneySources
  # Finds the user's active MoneySource mentioned in a piece of free text by
  # scanning it against each source's name, bank and recognition keyword
  # identifiers. Returns the first matching source, or nil when nothing
  # clearly matches.
  #
  #   MoneySources::Detector.call(user: user, text: "gasté 50 mil desde nequi")
  #
  # Used by ExpenseResolver (text/voice input) and the playground pipeline
  # (image/OCR input), so all channels detect sources the same way.
  class Detector
    ACCENT_MAP = { "á" => "a", "é" => "e", "í" => "i", "ó" => "o", "ú" => "u", "ü" => "u" }.freeze

    # Generic payment-method vocabulary. When a text slice names one of these
    # without matching a registered source, the expense explicitly stated its
    # payment method and must not inherit another expense's source.
    PAYMENT_TERMS = %w[efectivo tarjeta transferencia cash banco cheque].freeze

    def self.call(user:, text:, sources: nil)
      new(user: user, sources: sources).call(text)
    end

    def initialize(user:, sources: nil)
      @sources = sources || MoneySource.active.where(user: user)
                            .includes(recognition: :recognition_identifiers).to_a
    end

    def call(text)
      best_match(text)&.first
    end

    # Every registered source whose identifiers match the text, in the same
    # order the sources were loaded.
    def matching_sources(text)
      scored_matches(text).map(&:first)
    end

    # The strongest match: the source with the most matched values (name,
    # bank, confirmed keywords); the first-loaded source wins ties.
    def best_match(text)
      scored_matches(text).max_by { |_, matched| matched.size }
    end

    # [source, matched_values] pairs for every source with at least one
    # matched value, in load order.
    def scored_matches(text)
      return [] if text.blank?

      clean = normalize_text(text)
      @sources.filter_map do |source|
        matched = matched_values(source, clean)
        next if matched.empty?

        [ source, matched ]
      end
    end

    # True when the text explicitly names a payment method, even if no
    # registered source matches it ("pagué con tarjeta Infinite").
    def self.payment_mention?(text)
      return false if text.blank?

      clean = normalize_text_static(text)
      PAYMENT_TERMS.any? { |term| clean.match?(/\b#{term}\b/) }
    end

    def self.normalize_text_static(text)
      text.to_s.downcase.gsub(/[áéíóúü]/, ACCENT_MAP).squish
    end

    private

    # Values of the source (name, bank, confirmed keyword identifiers) that
    # appear in the text; the count drives the ranking.
    def matched_values(source, clean)
      values = [ source.name, source.bank ]
      values.concat(source.recognition_identifiers.select(&:keyword?).map(&:value))
      values.compact.map { |value| normalize_text(value) }
            .uniq
            .select { |value| value.present? && clean.match?(/\b#{Regexp.escape(value)}\b/) }
    end

    def normalize_text(text)
      self.class.normalize_text_static(text)
    end
  end
end

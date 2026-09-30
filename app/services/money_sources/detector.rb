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

    # The candidate pool defaults to the user's PAYMENT SOURCES only: the
    # detector is used to attribute expenses, and a loan ("compré con mi
    # crédito vehículo") must never match as the paying source. Call sites
    # may override the pool explicitly for other operations (funding,
    # debt payment) once those flows land.
    def initialize(user:, sources: nil)
      # order(:id) pins "first-created wins ties"; without an explicit ORDER
      # row loading order is unspecified and the tie-break becomes a flake.
      @sources = sources || MoneySource.active.payment_sources
                         .includes(:recognition_identifiers, recognition: :recognition_identifiers)
                         .order(:id).to_a
    end

    def call(text)
      best_match(text)&.first
    end

    # True when the fragment actually names this source: every word of at
    # least one of its identifier values (name or confirmed keyword) appears
    # in the fragment's tokens, filler words notwithstanding ("con la cuenta
    # de Davibank" grounds "cuenta davibank").
    def grounded_in?(source, text)
      fragment_tokens = normalize_text(text).split
      return false if fragment_tokens.empty?

      identifier_values = [ source.name, *source.recognition_identifiers.select(&:keyword?).map(&:value) ]
      identifier_values.compact.map { |value| normalize_text(value).split }
                       .any? { |value_tokens| value_tokens.present? && (value_tokens - fragment_tokens).empty? }
    end

    # Every registered source whose identifiers match the text, in the same
    # order the sources were loaded.
    def matching_sources(text)
      scored_matches(text).map(&:first)
    end

    # The strongest match: highest weighted score; the first-loaded source
    # wins ties.
    def best_match(text)
      scored_matches(text).max_by { |_, score| score }
    end

    # [source, score] pairs for every source with a positive score, in load
    # order. Explicit recognition signals (the source's name or a confirmed
    # keyword identifier) weigh 2 points each; a bank mention weighs 1.
    def scored_matches(text)
      return [] if text.blank?

      clean = normalize_text(text)
      @sources.filter_map do |source|
        score = match_score(source, clean)
        next if score.zero?

        [ source, score ]
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

    # How strongly the text names this source: each matched identifier value
    # (name or confirmed keyword) earns 2 points — the user explicitly taught
    # the system that word — while a bank mention earns 1 (institutional
    # context only, shared by every product of the same bank).
    IDENTIFIER_POINTS = 2
    BANK_POINTS = 1

    def match_score(source, clean)
      identifier_values = [ source.name, *source.recognition_identifiers.select(&:keyword?).map(&:value) ]
      identifier_points = identifier_values.compact.map { |value| normalize_text(value) }
                                           .uniq
                                           .count { |value| value.present? && clean.match?(/\b#{Regexp.escape(value)}\b/) }
      bank_points = source.bank.present? && clean.match?(/\b#{Regexp.escape(normalize_text(source.bank))}\b/) ? 1 : 0

      identifier_points * IDENTIFIER_POINTS + bank_points * BANK_POINTS
    end

    def normalize_text(text)
      self.class.normalize_text_static(text)
    end
  end
end

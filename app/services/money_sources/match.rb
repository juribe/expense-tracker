# frozen_string_literal: true

module MoneySources
  # Matches an incoming transaction to a MoneySource using Source Recognition
  # data and the source's own attributes. Returns a single MoneySource when
  # unambiguous, an array of candidates when ambiguous, and nil when nothing
  # matches.
  #
  #   MoneySources::Match.call(user: user, tag: "Tarjeta Clásica")
  #   MoneySources::Match.call(user: user, card_last_four: "1234", bank: "Bancolombia")
  #
  # Lookup semantics (values normalized with strip + downcase):
  #   tag            — equals a configured keyword identifier or the source name
  #   card_last_four — equals source.last_four (only the ending digits count)
  #   bank           — equals source.institution (normalized bank string)
  class Match
    def self.call(user:, **kwargs)
      new(user: user, **kwargs).call
    end

    def initialize(user:, tag: nil, card_last_four: nil, bank: nil)
      @user = user
      @tag = tag
      @card_last_four = card_last_four
      @bank = bank
    end

    def call
      sources = candidate_sources.to_a
      return nil if sources.empty?
      return sources.first if sources.one?

      sources
    end

    private

    # Resolves every lookup value against the source's recognition keywords,
    # its last-four digits and its institution.
    def candidate_sources
      values = lookup_values
      return MoneySource.none if values.empty?

      candidate_sources_scope.select { |source| values.any? { |value| source_matches_value?(source, value) } }
                             .uniq(&:id)
    end

    def candidate_sources_scope
      @user.money_sources.active.includes(recognition: :recognition_identifiers)
    end

    def lookup_values
      values = []
      values << normalize(@tag) if @tag.present?
      values << last_four if last_four.present?
      values << normalize(@bank) if @bank.present?
      values
    end

    def source_matches_value?(source, value)
      return true if value.match?(/\A\d{4}\z/) && source.last_four == value
      return true if source.institution == value
      return true if normalize(source.name) == value

      source.recognition_identifiers.any? do |id|
        id.kind == "keyword" && normalize(id.value) == value
      end
    end

    def last_four
      digits = @card_last_four.to_s.scan(/\d/).join
      digits[-4..] if digits.length >= 4
    end

    def normalize(value)
      value.to_s.strip.downcase
    end
  end
end

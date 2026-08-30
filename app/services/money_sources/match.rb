# frozen_string_literal: true

module MoneySources
  # Matches an incoming transaction to a MoneySource using normalized tags.
  # Returns a single MoneySource when unambiguous, an array of candidates when
  # the tag is ambiguous, and nil when nothing matches.
  #
  #   MoneySources::Match.call(user: user, tag: "Tarjeta Clásica")
  #   MoneySources::Match.call(user: user, card_last_four: "1234", bank: "Bancolombia")
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

    # Resolves every lookup value against the user's active MoneySource tags.
    # card_last_four/bank are legacy hints: they become ordinary tag lookups.
    def candidate_sources
      values = lookup_values
      return MoneySource.none if values.empty?

      values.flat_map { |value| sources_with_tag(value).to_a }.uniq(&:id)
    end

    def lookup_values
      values = []
      values << MoneySourceTag.normalize(@tag) if @tag.present?

      values << last_four if last_four.present?
      values << @bank.to_s.strip.downcase if @bank.present?
      values
    end

    def last_four
      digits = @card_last_four.to_s.scan(/\d/).join
      digits[-4..] if digits.length >= 4
    end

    def sources_with_tag(value)
      MoneySource.with_tag(value).where(user: @user)
    end
  end
end

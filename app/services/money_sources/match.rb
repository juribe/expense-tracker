# frozen_string_literal: true

module MoneySources
  # Matches an incoming transaction to a MoneySource using extracted
  # identifiers (card_last_four, bank). Returns the matched MoneySource or nil.
  #
  #   MoneySources::Match.call(user: user, card_last_four: "1234", bank: "Bancolombia")
  class Match
    def self.call(user:, card_last_four: nil, bank: nil)
      new(user: user, card_last_four: card_last_four, bank: bank).call
    end

    def initialize(user:, card_last_four: nil, bank: nil)
      @user = user
      @card_last_four = normalize_card(card_last_four)
      @bank = bank.to_s.strip.presence
    end

    def call
      match_by_card || match_by_bank
    end

    private

    def match_by_card
      return nil if @card_last_four.blank?

      sources = MoneySource
        .active
        .joins(:identifiers)
        .where(user: @user)
        .where(money_source_identifiers: { kind: "card_last_four", value: @card_last_four })

      sources.first if sources.one?
    end

    def match_by_bank
      return nil if @bank.blank?

      normalized_bank = @bank.downcase.strip
      sources = MoneySource
        .active
        .joins(:identifiers)
        .where(user: @user)
        .where(money_source_identifiers: { kind: "bank_name", value: normalized_bank })

      sources.first if sources.one?
    end

    def normalize_card(value)
      digits = value.to_s.scan(/\d/).join
      digits[-4..]&.then { |last4| last4.length == 4 ? last4 : nil }
    end
  end
end

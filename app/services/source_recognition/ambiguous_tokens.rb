# frozen_string_literal: true

module SourceRecognition
  # AmbiguousTokens
  # Alphanumeric tokens that appear in the names of SEVERAL payment sources
  # of the same user — the card-brand case ("Visa" on two cards of the same
  # bank). A token that matches several sources at once can never single one
  # out, so it is useless (and misleading) as a recognition identifier.
  #
  # Consumers (DiscoveryService keyword candidates, SuggestionEngine
  # name-derived keywords) are responsible for rejecting these tokens, and
  # for not creating some tier of association later by a shared brand.
  class AmbiguousTokens
    class << self
      def for_user(user)
        return EMPTY_SET if user.nil?

        counts = user.money_sources
                     .payment_sources
                     .pluck(:name).flat_map { |name| TextNormalizer.name_tokens(name, stop_words: []) }
                     .tally
        counts.select { |_, count| count >= 2 }.keys.to_set
      end
    end

    EMPTY_SET = Set.new.freeze
  end
end

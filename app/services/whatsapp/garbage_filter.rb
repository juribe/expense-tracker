# frozen_string_literal: true

module Whatsapp
  # Deterministic pre-LLM filter: rejects keyboard-mash/gibberish messages so
  # they never reach the AI pipeline or the clarification resolver. Zero cost
  # (pure heuristics); anything not clearly garbage passes through.
  #
  #   Whatsapp::GarbageFilter.garbage?("sdksmdksmnkd skd kjs kdj") # => true
  #   Whatsapp::GarbageFilter.garbage?("almuerzo con Juan")        # => false
  #
  # A message is garbage when it carries no expense signal (no digits, no
  # money words, no known intent keyword) AND looks like noise: very low
  # lexical diversity, repeated tokens, vowel-less long words or long
  # consonant runs. Cancel commands and short coherent replies always pass.
  module GarbageFilter
    MONEY_SIGNAL = /[\d]|\$|usd|cop|mil|lucas|k\b|pesos|gast[eo]|pag[úuoé]|compr[eoé]|pagué|transfer[íi]|recarg|almuerz|cena|desayun|mercado|taxi|uber|david|nequi|banc|tarjeta|efectivo|categoria|categoría|fuente|cancel/i

    VOWELS = /[aeiouáéíóúü]/i

    class << self
      def garbage?(text)
        text = text.to_s.strip
        return false if text.empty?
        return false if text.match?(/\Acancela/i)

        return true if no_expense_signal_and_noisy?(text)

        false
      end

      private

      def no_expense_signal_and_noisy?(text)
        return false if text.match?(MONEY_SIGNAL)

        noisy?(text)
      end

      def noisy?(text)
        tokens = text.downcase.split(/\s+/)
        return true if tokens.size >= 3 && unique_ratio(tokens) < 0.4
        return true if tokens.any? { |token| token.size >= 6 && !token.match?(VOWELS) }
        return true if tokens.any? { |token| token.match?(/[bcdfghjklmnñpqrstvwxyz]{5,}/i) }
        return true if token_repetition?(tokens)

        false
      end

      def unique_ratio(tokens)
        tokens.uniq.size.to_f / tokens.size
      end

      def token_repetition?(tokens)
        return false if tokens.size < 3

        counts = tokens.tally
        counts.values.max >= 3
      end
    end
  end
end

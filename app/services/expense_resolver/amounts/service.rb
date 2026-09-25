# frozen_string_literal: true

module ExpenseResolver
  module Amounts
    class Service
      NUMBER_WORDS = {
        "un" => 1, "una" => 1, "uno" => 1,
        "dos" => 2, "tres" => 3, "cuatro" => 4, "cinco" => 5, "seis" => 6,
        "siete" => 7, "ocho" => 8, "nueve" => 9, "diez" => 10, "once" => 11,
        "doce" => 12, "trece" => 13, "catorce" => 14, "quince" => 15,
        "veinte" => 20, "treinta" => 30, "cuarenta" => 40, "cincuenta" => 50,
        "sesenta" => 60, "setenta" => 70, "ochenta" => 80, "noventa" => 90,
        "cien" => 100, "ciento" => 100, "doscientos" => 200, "trescientos" => 300,
        "cuatrocientos" => 400, "quinientos" => 500, "seiscientos" => 600,
        "setecientos" => 700, "ochocientos" => 800, "novecientos" => 900
      }.freeze

      NUMBER_WORD_ALTERNATION = NUMBER_WORDS.keys.sort_by(&:length).reverse.join("|")

      # Matches amounts such as: 50.000 | 50,000 | 1'200.000 (grouped thousands),
      # medio millon, cuarto de millon, "50 mil", "cincuenta mil", "50 lucas",
      # "80k", "500 pesos" and plain integers or decimals.
      AMOUNT_REGEX = /
        (?<amount>
            \d{1,3}(?:['.,]\s?\d{3})+                                     |
            medio\s+millon                                                |
            (?:un\s+)?cuarto\s+de\s+millon                                |
            (?:\d+(?:[.,]\d+)?|(?:#{NUMBER_WORD_ALTERNATION})(?:\s+y\s+(?:#{NUMBER_WORD_ALTERNATION}))*)\s*(?:mil|lucas|luca)\b |
            \d+\s*k\b                                                     |
            \d+(?:[.,]\d+)?\s*(?:pesos|cop)\b                             |
            \d+(?:\.\d{1,2})?
        )
      /x.freeze

      def self.scan_amounts(text)
        results = []
        position = 0
        while (match = AMOUNT_REGEX.match(text, position))
          results << { start: match.begin(0), end: match.end(0), raw: match[:amount].strip }
          position = match.end(0)
        end
        results
      end

      # Returns [BigDecimal value, confidence].
      #
      # colloquial: true applies the chat slang rule: a bare integer without a
      # mil/lucas/k companion is read as thousands ("me gasté 100 en gasolina"
      # = 100000) when it is too small to be a real COP spend. Receipts, bank
      # statements and every image pipeline keep exact values (flag off).
      def self.interpret_amount(raw, colloquial: false)
        text = raw.gsub(/\s+/, " ").strip

        if text.match?(/\A\d{1,3}(?:['.,]\s?\d{3})+\z/)
          return [ text.delete("'.,").to_d, 0.95 ]
        elsif text.match?(/\Amedio\s+millon\z/)
          return [ 500_000, 0.95 ]
        elsif text.match?(/\A(?:un\s+)?cuarto\s+de\s+millon\z/)
          return [ 250_000, 0.9 ]
        elsif (multiplier = text.match(/\A(.+?)\s*(lucas|luca|mil)\z/))
          base, word_confidence = multiplier_base(multiplier[1])
          slang = multiplier[2].match?(/luca/)
          return [ base * 1000, [ word_confidence, slang ? 0.85 : 0.95 ].min ]
        elsif (kilos = text.match(/\A(\d+)\s*k\z/))
          return [ kilos[1].to_i * 1000, 0.85 ]
        elsif (plain = text.match(/\A(\d+)(?:[.,](\d{1,2}))?\s*(pesos|cop)?\z/))
          cents = plain[2]
          value = plain[1].to_d
          value += cents.to_d / 100 if cents
          unit = plain[3]

          if colloquial && unit.nil? && cents.nil? && value.positive? && value < 1_000
            return [ value * 1000, 0.7 ]
          end

          return [ value, unit ? 0.95 : 0.7 ]
        end

        [ text.scan(/\d+/).first.to_i, 0.5 ]
      end

      # Base for "mil"/"lucas" multipliers: digits ("50"), decimals ("1,5") or
      # number words ("cincuenta").
      def self.multiplier_base(token)
        token = token.strip
        if token.match?(/\A\d+(?:[.,]\d+)?\z/)
          return [ token.tr(",", ".").to_d, 0.95 ]
        end

        sum = token.split(/\s+y\s*/).sum { |word| NUMBER_WORDS[word].to_i }
        [ sum.to_d, 0.75 ]
      end
    end
  end
end

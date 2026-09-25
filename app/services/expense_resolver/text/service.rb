# frozen_string_literal: true

module ExpenseResolver
  module Text
    class Service
      DATE_WORDS = %w[lunes martes miercoles jueves viernes sabado domingo hoy ayer anteayer el esta este].to_set.freeze

      FILLER_WORDS = %w[
        me yo mi gaste gasto gastamos gasta pague pagar compre compro
        en de del al la las los un una unos unas que con para por y o
        a tambien solo fueron era son es
      ].to_set.freeze

      ACCENT_MAP = { "á" => "a", "é" => "e", "í" => "i", "ó" => "o", "ú" => "u", "ü" => "u" }.freeze

      # Trailing payment clauses describe how the whole purchase was paid, not
      # what was bought ("12.500 en cafe, todo con davibank"), so everything
      # from the clause on is cut. Money-source detection reads the full text.
      # Quantifier forms ("todo con") need a separator to avoid clipping
      # phrases like "todo con queso"; participles ("pagado con") stand alone.
      PAYMENT_CLAUSE_REGEX = /(?:[,;]\s*\b(?:todos?|ambas?|ambos?)|\b(?:pagad[oa]s?))\s+(?:con|desde|en|mediante|usando)\b/

      def self.normalize_text(text)
        text.to_s.downcase.gsub(/[áéíóúü]/, ACCENT_MAP).squish
      end

      def self.clean_description(text)
        stripped = text.to_s
        if (clause = stripped.match(PAYMENT_CLAUSE_REGEX))
          stripped = stripped[0...clause.begin(0)]
        end
        tokens = normalize_text(stripped).scan(/[a-zñ0-9]+/).reject do |token|
          FILLER_WORDS.include?(token) || DATE_WORDS.include?(token) || token.match?(/\A\d+\z/) || %w[lunes martes miercoles jueves viernes sabado domingo].include?(token)
        end
        titleize_words(tokens.join(" ")).truncate(80)
      end

      def self.titleize_words(text)
        text.to_s.split.map(&:capitalize).join(" ")
      end
    end
  end
end

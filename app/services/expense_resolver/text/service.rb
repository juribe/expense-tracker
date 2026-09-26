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

      # Motion and meal verbs describe the trip, not the purchase ("almuerzo
      # salí", "parqueadero salimos"). They are dropped wherever they appear
      # so descriptions never end on them.
      ACTION_WORDS = %w[
        sali salimos fui fuimos lleve llevo pase puse pongo
        almorce desayune cene almorzamos desayunamos cenamos
        pagamos compramos
        recargue recargaron devolvieron devolucion
      ].to_set.freeze

      ACCENT_MAP = { "á" => "a", "é" => "e", "í" => "i", "ó" => "o", "ú" => "u", "ü" => "u" }.freeze

      # Trailing payment clauses describe how the purchase was paid, not what
      # was bought ("12.500 en cafe, todo con davibank"), so everything from
      # the clause on is cut. Money-source detection reads the full text.
      # Quantifier forms ("todo con") need a separator to avoid clipping
      # phrases like "todo con queso"; participles ("pagado con") and the
      # per-name form ("el restaurante lo pagué con la cuenta...") stand alone.
      PAYMENT_CLAUSE_REGEX = /(?:[,;]\s*\b(?:todos?|ambas?|ambos?)|\b(?:pagad[oa]s?))\s+(?:con|desde|en|mediante|usando)\b/

      # The per-name variant: "El restaurante lo pagué con la cuenta davibank".
      NAMED_PAYMENT_CLAUSE_REGEX = /[,;.]\s*(?:el|la|los|las)?\s*\w[\wáéíóúñ]*\s+lo\s+pag\p{L}*\s+con\b/i

      # Strips trailing payment clauses ("...todo con davibank", "...pagado
      # con visa", "El restaurante lo pagué con la cuenta...") from a text
      # slice. Used for descriptions and for scoping source attribution.
      def self.cut_payment_clause(text)
        stripped = text.to_s
        if (clause = stripped.match(PAYMENT_CLAUSE_REGEX))
          stripped[0...clause.begin(0)]
        elsif (named_clause = stripped.match(NAMED_PAYMENT_CLAUSE_REGEX))
          stripped[0...named_clause.begin(0)]
        else
          stripped
        end
      end

      def self.normalize_text(text)
        text.to_s.downcase.gsub(/[áéíóúü]/, ACCENT_MAP).squish
      end

      def self.clean_description(text)
        stripped = cut_payment_clause(text)
        tokens = normalize_text(stripped).scan(/[a-zñ0-9]+/).reject do |token|
          FILLER_WORDS.include?(token) || ACTION_WORDS.include?(token) || DATE_WORDS.include?(token) || token.match?(/\A\d+\z/) || %w[lunes martes miercoles jueves viernes sabado domingo].include?(token)
        end
        titleize_words(tokens.join(" ")).truncate(80)
      end

      def self.titleize_words(text)
        text.to_s.split.map(&:capitalize).join(" ")
      end
    end
  end
end

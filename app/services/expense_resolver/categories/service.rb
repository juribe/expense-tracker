# frozen_string_literal: true

module ExpenseResolver
  module Categories
    class Service
      SYNONYM_GROUPS = [
        { canonical: "Restaurants", keywords: %w[restaurant restaurants restaurantes almuerzo comida cena desayuno lunch snack pizza hamburguesa cafe cafeteria bar] },
        { canonical: "Groceries", keywords: %w[groceries grocery mercado supermercado super compras frutas verduras tienda] },
        { canonical: "Parking", keywords: %w[parking parqueadero parqueo estacionamiento] },
        { canonical: "Gasoline", keywords: %w[gasolina gasoline gasolinera combustible nafta] },
        { canonical: "Transportation", keywords: %w[transporte transportation bus taxi uber metro transmilenio pasaje peaje] },
        { canonical: "Entertainment", keywords: %w[entretenimiento entertainment cine pelicula fiesta concierto juegos] },
        { canonical: "Health", keywords: %w[salud health farmacia medicina doctor medico hospital clinica] },
        { canonical: "Education", keywords: %w[educacion education universidad colegio libros matricula curso] },
        { canonical: "Housing", keywords: %w[housing hogar casa arriendo renta alquiler servicios luz agua internet vivienda apartamento mantenimiento administracion predial] },
        { canonical: "Pet Care", keywords: %w[pets mascotas mascota perro gato veterinaria veterinario] },
        { canonical: "Clothing", keywords: %w[clothing ropa zapatos camisa vestido] },
        { canonical: "Travel", keywords: %w[travel viaje hotel avion vuelo equipaje] },
        { canonical: "Others", keywords: %w[otros others varios miscelaneo] }
      ].freeze

      Resolution = Struct.new(:category, :suggested_name, :confidence)

      def self.resolve_category(description, context, categories)
        haystack = "#{context} #{description}".squish

        group = best_matching_group(haystack)
        if group
          existing = find_existing_category(group, haystack, categories)
          return Resolution.new(existing, nil, 0.95) if existing

          return Resolution.new(nil, group[:canonical], 0.6)
        end

        direct = categories.find do |category|
          name = Text::Service.normalize_text(category.name)
          normalized = Text::Service.normalize_text(description.to_s)
          next false if normalized.blank?

          name == normalized ||
            (name.length >= 5 && normalized.length >= 5 && name[0, 5] == normalized[0, 5])
        end
        return Resolution.new(direct, nil, 0.9) if direct

        Resolution.new(nil, description.presence, 0.4)
      end

      def self.best_matching_group(haystack)
        best = nil
        best_length = 0
        SYNONYM_GROUPS.each do |group|
          keyword = best_matching_keyword(haystack, group)
          next unless keyword

          if keyword.length > best_length
            best_length = keyword.length
            best = group
          end
        end
        best
      end

      def self.best_matching_keyword(haystack, group)
        group[:keywords]
          .select { |word| haystack.match?(keyword_pattern(word)) }
          .max_by(&:length)
      end

      # Tolerates plural/singular variants ("restaurante"/"restaurantes").
      def self.keyword_pattern(word)
        stem = word.sub(/es\z/, "").sub(/s\z/, "")
        /\b#{Regexp.escape(stem)}(?:e?s)?\b/
      end

      # Maps the canonical group label to a user category by exact name, then by
      # the keyword that actually matched the message. The canonical label and its
      # Spanish alias (from the resolver, e.g. "Housing" -> "Vivienda") are tried
      # first; only the specific matched keyword is checked against category names,
      # so "arriendo" never matches "Servicios públicos" through the generic
      # "servicios" keyword.
      def self.find_existing_category(group, haystack, categories)
        names = [ group[:canonical] ]
        names.concat(Array(::Categories::ClosestResolver::ALIASES[group[:canonical].downcase]))

        names.each do |name|
          hit = categories.find { |category| Text::Service.normalize_text(category.name) == Text::Service.normalize_text(name) }
          return hit if hit
        end

        keyword = best_matching_keyword(haystack, group)
        return nil if keyword.nil? || keyword.length < 5

        categories.find do |category|
          name = Text::Service.normalize_text(category.name)
          name.include?(keyword) || name.match?(keyword_pattern(keyword))
        end
      end
    end
  end
end

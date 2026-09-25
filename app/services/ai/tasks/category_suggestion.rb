# frozen_string_literal: true

module Ai
  module Tasks
    # Second-pass category resolution for parsed expenses whose category came
    # back null. Only the missing entries are sent, each resolved
    # independently; unclear purposes map to nil so the caller keeps the
    # suggestion-free state.
    #
    # input:   [{ "index" => 0, "description" => "pago de ropa" }, ...]
    # context: { user: } (optional)
    # data:    { "0" => "Ropa", "1" => nil }
    class CategorySuggestion < Base
      def timeout
        25
      end

      def messages(input, _context)
        [
          { role: "system", content: system_prompt },
          { role: "user", content: Array(input).to_json }
        ]
      end

      def parse(content, input, _context)
        suggestions = parse_json(content)
        # Small models often answer a one-item batch without the array wrapper.
        suggestions = [ suggestions ] if suggestions.is_a?(Hash) && suggestions.key?("category_suggestion")
        raise InvalidResponse, "missing suggestions array" unless suggestions.is_a?(Array)

        known_indices = Array(input).map { |item| suggestion_key(item) }.compact
        data = {}
        confidences = []

        suggestions.each do |entry|
          next unless entry.is_a?(Hash)

          index = entry["index"].to_s
          next if index.empty?
          next unless known_indices.include?(index)

          confidences << (entry["confidence"].is_a?(Numeric) ? Float(entry["confidence"]).clamp(0.0, 1.0) : 0.5)
          data[index] = entry["category_suggestion"].is_a?(String) ? entry["category_suggestion"].strip.presence : nil
        end

        raise InvalidResponse, "no usable suggestion entries" if data.empty?

        { data: data, confidence: confidences.min }
      end

      private

      def suggestion_key(item)
        value = item["index"] || item[:index]
        value.to_s if value
      end

      def system_prompt
        <<~PROMPT
          Para cada gasto, sugiere una categoría general y reutilizable.
          La categoría nombra el tipo de gasto (qué se compró o pagó), no la
          acción ni el destinatario. Ejemplos: "pago de ropa" → Ropa;
          "arreglo de reloj" → Accesorios; "por concepto de videojuegos" → Videojuegos.
          No copies la descripción. Si el propósito no es claro, usa null.
          Devuelve solo JSON válido.

          Salida:

          [{"index":0,"category_suggestion":"Ropa","confidence":0.95},
            {"index":1,"category_suggestion":null,"confidence":0.3}]
        PROMPT
      end
    end
  end
end

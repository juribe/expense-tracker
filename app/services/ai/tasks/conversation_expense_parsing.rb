# frozen_string_literal: true

module Ai
  module Tasks
    # Single-AI-call natural-language expense parsing. The complete free-text
    # input goes to the model once; it returns every distinct expense with
    # original text, amount, date, description, category and an optional money
    # source hint. No separate splitting or categorization calls.
    #
    #   input:   "Ayer compré mercado por 180 mil en Éxito, después pagué 50 mil de gasolina"
    #   context: { user:, today: Date, categories: [Category, ...] }
    #   data:    [ { original_text:, amount:, date:, description:, category:,
    #                money_source_hint: }, ... ]
    #   confidence: model-provided, the lowest per-expense confidence in the set.
    class ConversationExpenseParsing < Base
      def timeout
        25
      end

      def messages(input, context)
        [
          { role: "system", content: system_prompt(context) },
          { role: "user", content: input.to_s }
        ]
      end

      def parse(content, _input, _context)
        payload = parse_json(content)
        entries = payload.is_a?(Array) ? payload : payload["expenses"]
        raise InvalidResponse, "missing 'expenses' array" unless entries.is_a?(Array) && entries.any?

        entries = entries.filter_map do |entry|
          next unless entry.is_a?(Hash)

          entry.transform_keys(&:to_s).transform_values { |v| v.is_a?(String) ? v.strip : v }
        end
        raise InvalidResponse, "no usable expense entries" if entries.empty?

        confidences = entries.map { |entry| confidence_of(entry) }
        entries.each { |entry| entry.delete("confidence") }

        { data: entries, confidence: confidences.min }
      end

      private

      def confidence_of(entry)
        value = entry["confidence"]
        value.is_a?(Numeric) ? Float(value).clamp(0.0, 1.0) : 0.5
      end

      def system_prompt(context)
        today = (context[:today] || Date.current).to_date.iso8601
        categories = Array(context[:categories]).map { |category|
          category.respond_to?(:name) ? category.name : category.to_s
        }.join(", ")

        <<~PROMPT
          Eres un asistente especializado en registrar gastos a partir de texto en lenguaje natural.

          El usuario puede describir uno o varios gastos en un mismo texto.
          Debes identificar cada gasto individual y devolverlos como objetos separados.

          Para cada gasto debes extraer:

          - original_text: conserva la parte del texto original del usuario que corresponde a este gasto.
            No inventes un resumen ni cambies innecesariamente las palabras del usuario.
          - amount: monto normalizado en pesos colombianos (COP).
            Ejemplos:
            "50 mil" = 50000
            "50 lucas" = 50000
            "50k" = 50000
            "50 barras" = 50000
            "50.000 pesos" = 50000
          - date: resuelve fechas relativas como "hoy", "ayer", "anteayer",
            "el lunes" o "hace 3 días" utilizando la fecha actual proporcionada.
            Formato: YYYY-MM-DD.
          - description: descripción breve y natural de qué fue el gasto.
          - category: exactamente una de las categorías proporcionadas.
          - money_source_hint: texto que ayude a identificar el medio de pago mencionado
            por el usuario, por ejemplo "la clásica", "la Visa",
            "tarjeta terminada en 1234" o "cuenta Bancolombia".
            Debe ser null si no se menciona.
          - confidence: qué tan seguro estás de que el gasto se extrajo correctamente,
            un número entre 0 y 1 (más alto = más seguro).
            Usa valores bajos cuando parte de la información sea ambigua o haya
            que suponerla.

          Reglas:

          - Fecha actual: #{today}
          - Moneda: COP
          - Categorías permitidas: [#{categories}]
          - Categoría: intenta primero asignar el gasto a una de las categorías proporcionadas.
          - Si ninguna de las categorías proporcionadas representa razonablemente el gasto,
            puedes sugerir una nueva categoría.
          - Las categorías sugeridas deben ser claras, generales y reutilizables.
          - No crees una categoría nueva simplemente porque el gasto podría pertenecer
            a una categoría existente.
          - No crees categorías demasiado específicas para un merchant o producto.
          - Si existe una categoría razonablemente adecuada, úsala en lugar de sugerir una nueva.
          - No inventes información.
          - No crees entidades de merchant ni IDs.
          - money_source_hint es solamente una pista textual; nunca es un ID de la base de datos.
          - Si varios productos pertenecen a una misma compra, deben formar un solo gasto,
            salvo que el usuario indique claramente que son pagos o transacciones diferentes.
          - Si el texto contiene varios gastos, devuelve todos.
          - Si el texto describe un solo gasto, devuelve un solo objeto.
          - Si no puedes determinar una fecha con suficiente certeza, usa null.
          - original_text debe permitir al usuario reconocer exactamente qué parte de su texto
            fue interpretada como ese gasto.

          Devuelve ÚNICAMENTE JSON válido con esta estructura:

          {
            "expenses": [
              {
                "original_text": "...",
                "amount": 50000,
                "date": "2026-09-16",
                "description": "gasolina",
                "category": "Transporte",
                "money_source_hint": null,
                "confidence": 0.9
              }
            ]
          }
        PROMPT
      end
    end
  end
end

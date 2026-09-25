# frozen_string_literal: true

module Ai
  module Tasks
    # Parse one or more expenses from natural-language text in a single AI call.
    #
    #   input:   "Ayer compré mercado por 180 mil en Éxito, después pagué 50 mil de gasolina"
    #   context: { user:, today: Date, categories: [Category, ...] }
    #   data:    [
    #     {
    #       original_text:,
    #       amount:,
    #       date:,
    #       description:,
    #       category:
    #     },
    #     ...
    #   ]
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

      def parse(content, input, context)
        payload = parse_json(content)
        entries = payload.is_a?(Array) ? payload : payload["expenses"]

        raise InvalidResponse, "missing 'expenses' array" unless entries.is_a?(Array) && entries.any?

        categories = Array(context[:categories])
        today = (context[:today] || Date.current).to_date

        expenses = entries.filter_map do |entry|
          next unless entry.is_a?(Hash)

          score = Expenses::ConfidenceCalculator.call(
            expense: ParsedExpense.build_expense(entry),
            input: input,
            categories: categories,
            today: today
          ).score

          ParsedExpense.build_expense(
            entry.merge("confidence" => score)
          )
        end

        raise InvalidResponse, "no usable expense entries" if expenses.empty?

        {
          data: expenses,
          confidence: expenses.map(&:confidence).min || 0.0
        }
      end

      private

      def system_prompt(context)
        today = (context[:today] || Date.current).to_date.iso8601

        categories = Array(context[:categories]).map do |category|
          category.respond_to?(:name) ? category.name : category.to_s
        end.join(", ")

        hint = context[:context].presence
        context_block = hint ? <<~CONTEXT : ""
          Contexto del procesamiento:
          #{hint}
          Usa esta información para entender el propósito del gasto, incluso si
          no aparece en el comprobante OCR.
        CONTEXT

        <<~PROMPT
          Extrae cada gasto distinto del mensaje del usuario.
          Devuelve cada transacción como un objeto de gasto separado.

          #{context_block}

          Hoy: #{today}
          Moneda: COP
          Categorías disponibles: [#{categories}]

          Para cada gasto devuelve:

          - original_text: la parte completa del mensaje original del usuario
            que pertenece a este gasto. Conserva las palabras originales cuando
            sea posible. Incluye descripción, valor, comercio, fecha y método
            de pago. No traduzcas, resumas ni inventes información.
          - amount: valor entero en COP. Ejemplos: "50 mil" = 50000,
            "50 lucas" = 50000, "50k" = 50000.
          - date: YYYY-MM-DD. Resuelve las fechas usando Hoy.
            Si no se menciona una fecha, usa Hoy.
          - description: descripción corta del gasto en el mismo idioma usado
            por el usuario. No traduzcas ni inventes información.
          - category: usa una categoría de la lista solo si realmente corresponde
            al propósito del gasto. Si ninguna categoría encaja claramente,
            devuelve null. Nunca fuerces la categoría más parecida.

          Una categoría puede representar un tipo o subtipo normal del gasto.
          Ejemplos:
          - "gasolina" → "Transporte"
          - "arreglo de llantas" → "Transporte"
          - "matrícula universitaria" → "Educación"
          - "compré comida" → "Comida"
          - "pago de ropa" → null
          - "pago manicure" → null

          El destinatario, comercio, método de pago o tipo de transferencia
          no determina por sí solo el propósito del gasto.

          Reglas:
          - Devuelve cada transacción distinta.
          - Mantén varios artículos como un solo gasto cuando pertenezcan a
            la misma compra.
          - Separa las transacciones aunque usen el mismo método de pago.
          - Un método de pago mencionado una vez puede aplicar a varios gastos.
          - No crees un gasto separado para un método de pago.
          - No inventes información faltante.
          - No crees IDs ni entidades de base de datos.
          - original_text debe provenir del mensaje del usuario.
          - Devuelve únicamente JSON válido. Sin markdown ni explicaciones.
          - Si no se proporciona una fecha, usa Hoy.
          - No uses null para date salvo que la fecha proporcionada sea
            ambigua y no pueda resolverse razonablemente.

          Salida:

          {
            "expenses": [
              {
                "original_text": "...",
                "amount": 50000,
                "date": "2026-09-16",
                "description": "gasolina",
                "category": "Transporte"
              }
            ]
          }
        PROMPT
      end
    end
  end
end
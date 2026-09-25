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
          Contexto del procesamiento (usar para entender el propósito del gasto):
          #{hint}
        CONTEXT

        <<~PROMPT
          Extrae cada gasto distinto del mensaje del usuario. Un objeto por transacción.

          #{context_block}

          Hoy: #{today}
          Moneda: COP
          Categorías disponibles: [#{categories}]

          Campos por gasto:
          - original_text: fragmento exacto del mensaje original para ese gasto
            (descripción, valor, comercio, fecha, método de pago). No traduzcas
            ni resumas.
          - amount: entero COP. "50 mil", "50 lucas" y "50k" = 50000.
          - date: YYYY-MM-DD. Cada gasto usa la expresión de fecha más
            cercana mencionada antes de él; una fecha como "ayer" aplica a
            todos los gastos siguientes hasta que se mencione otra fecha.
            Usa Hoy solo si el mensaje no menciona ninguna fecha; null solo
            si es ambigua.
          - description: corto, en el idioma del usuario. No traduzcas ni inventes.
          - category: de la lista solo si corresponde claramente al propósito;
            si no encaja, null. Nunca fuerces la más parecida. El comercio,
            destinatario o método de pago no definen el propósito.
            Ejemplos: "gasolina" → "Transporte", "matrícula universitaria" →
            "Educación", "pago de ropa" → null.

          Reglas:
          - Varios artículos de una misma compra = un solo gasto. Transacciones
            distintas se separan aunque compartan método de pago; un método
            mencionado una vez puede aplicar a varios y nunca es un gasto propio.
          - original_text debe cubrir solo ese gasto: si hay varios gastos,
            nunca repitas el mensaje completo en cada objeto.
          - No inventes información ni crees IDs o entidades de base de datos.
          - Devuelve únicamente JSON válido, sin markdown ni explicaciones:

          {"expenses": [{"original_text": "...", "amount": 50000,
            "date": "#{today}", "description": "gasolina", "category": "Transporte"}]}
        PROMPT
      end
    end
  end
end
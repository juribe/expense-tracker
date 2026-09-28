# frozen_string_literal: true

module Ai
  module Tasks
    # Interpret a WhatsApp reply to a pending MULTI-expense clarification
    # session. The resolver always works with ARRAYS: it receives the pending
    # candidates (indexed 1..n), their resolved and missing fields, the
    # previous question and the reply; it returns one resolution entry per
    # candidate it could safely match. Only missing fields are extracted —
    # already resolved fields and unknown candidates are never touched.
    #
    #   input:   "éxito con tarjeta, gasolina efectivo y el restaurante con davibank"
    #   context: { user:, candidates: [{ index:, description:, amount:, date:,
    #              category:, money_source:, missing_fields: [...] }],
    #              question:, original_message:, categories: [...],
    #              money_source_identifiers: [...], today: Date }
    #   data:    { resolutions: [ { index:, resolved: { amount|date|description|
    #              category|money_source_hint }, unresolved: true|false } ],
    #              new_expense_text: "50 mil en supermercado con efectivo"|nil }
    class ClarificationResolution < Base
      ALLOWED_UPDATE_KEYS = %w[amount date description category money_source_hint].freeze

      # Default tiers (%i[cheap strong]): the strong tier may be disabled via
      # AI_DISABLE_STRONG_TIER, and a strong-only task would then have no
      # usable tier at all.
      def messages(input, context)
        [
          { role: "system", content: system_prompt(context) },
          { role: "user", content: input.to_s }
        ]
      end

      def parse(content, _input, _context)
        payload = parse_json(content)
        resolutions = payload.is_a?(Array) ? payload : payload["resolutions"]
        raise InvalidResponse, "missing 'resolutions' array" unless resolutions.is_a?(Array)

        entries = resolutions.filter_map do |entry|
          next unless entry.is_a?(Hash) && entry["index"].present?

          updates = (entry["resolved"] || {}).slice(*ALLOWED_UPDATE_KEYS)
          {
            index: entry["index"].to_i,
            resolved: updates,
            unresolved: entry["unresolved"] == true || updates.blank?
          }
        end

        {
          data: {
            resolutions: entries,
            new_expense_text: payload.is_a?(Hash) ? payload["new_expense_text"].presence : nil
          },
          confidence: 1.0
        }
      end

      private

      def system_prompt(context)
        today = (context[:today] || Date.current).to_date.iso8601
        candidates = Array(context[:candidates]).map do |candidate|
          <<~CANDIDATE.chomp
            #{candidate[:index]}. #{candidate[:description].presence || '(sin descripción)'} | monto=#{candidate[:amount].presence || 'desconocido'} | fecha=#{candidate[:date].presence || 'desconocida'} | categoría=#{candidate[:category].presence || 'falta'} | medio de pago=#{candidate[:money_source].presence || 'falta'} | faltan=[#{Array(candidate[:missing_fields]).join(', ')}]
          CANDIDATE
        end.join("\n")
        categories = Array(context[:categories]).map(&:to_s).join(", ")
        sources = Array(context[:money_source_identifiers]).map(&:to_s).reject(&:blank?).uniq.join(", ")
        question = context[:question].to_s
        original = context[:original_message].to_s

        <<~PROMPT
          Eres un asistente de gastos. El usuario registró varios gastos por
          WhatsApp y algunos están incompletos. El usuario ahora responde una
          pregunta de aclaración que puede cubrir a varios gastos a la vez.

          Gastos pendientes (numerados):
          #{candidates}

          Mensaje original de los gastos: "#{original}"
          Pregunta hecha al usuario: "#{question}"
          Hoy: #{today}

          Categorías disponibles: [#{categories}]
          Fuentes de dinero registradas: [#{sources}]

          Devuelve JSON con esta forma:
          {"resolutions": [{"index": 1, "resolved": {...}}, {"index": 2, "unresolved": true}],
           "new_expense_text": null}

          Reglas:
          - Un elemento por gasto al que la respuesta aporta información,
            con "index" igual al número del gasto.
          - En "resolved" llena SOLO campos de la lista de faltantes de ese
            gasto: amount (entero COP, "50 mil" = 50000), date (YYYY-MM-DD,
            relativo a hoy), description (corto), category (solo de la lista;
            null si ninguna encaja), money_source_hint (solo de las fuentes
            registradas; null si no corresponde).
          - Referencias naturales: "el primero", "el segundo", "los dos
            últimos", "el resto", "todos con tarjeta", o el nombre del gasto
            ("gasolina efectivo"). Márcalos con el index correcto.
          - Si la respuesta no aclara un gasto (o es ambigua para él), NO lo
            incluyas en resolutions. Nunca inventes valores.
          - Si parte del mensaje es un gasto NUEVO distinto (no aclara los
            pendientes), pon ese fragmento exacto en "new_expense_text";
            si no hay gasto nuevo, null.
          - Devuelve únicamente JSON válido, sin markdown.
        PROMPT
      end
    end
  end
end

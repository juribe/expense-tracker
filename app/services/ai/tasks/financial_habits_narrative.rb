# frozen_string_literal: true

module Ai
  module Tasks
    class FinancialHabitsNarrative < Base
      def timeout
        30
      end

      def messages(input, context)
        [
          { role: "system", content: system_prompt(context) },
          { role: "user", content: input.to_json }
        ]
      end

      def parse(content, _input, context)
        payload = parse_json(content)
        raise InvalidResponse, "AI response is not an object" unless payload.is_a?(Hash)

        summary = payload["summary"].to_s.strip
        raise InvalidResponse, "missing summary" if summary.blank?
        raise InvalidResponse, "summary contains numeric figures" if summary.match?(/\d/)

        allowed = Array(context[:allowed_references]).map(&:to_s)
        highlights = Array(payload["highlights"]).filter_map do |entry|
          next unless entry.is_a?(Hash)

          reference = entry["reference"].to_s
          next unless allowed.include?(reference)

          explanation = entry["explanation"].to_s.strip
          recommendation = entry["recommendation"].to_s.strip
          next if explanation.blank? && recommendation.blank?
          next if explanation.match?(/\d/) || recommendation.match?(/\d/)

          {
            "reference" => reference,
            "explanation" => explanation,
            "recommendation" => recommendation
          }
        end

        { data: { "summary" => summary, "highlights" => highlights }, confidence: nil }
      end

      private

      def system_prompt(context)
        references = Array(context[:allowed_references])
        <<~PROMPT
          Eres el analista de finanzas personales de Yogasto. Recibes patrones de
          comportamiento ya detectados por el backend.

          Reglas obligatorias:
          - No inventes cifras, comercios, categorías ni movimientos.
          - No escribas importes ni porcentajes en tu texto.
          - No juzgues al usuario ni uses lenguaje culpabilizante.
          - Usa un tono neutral, respetuoso y fácil de entender, en español.
          - Para cada patrón usa exactamente una de las referencias permitidas.

          Referencias permitidas: [#{references.join(", ")}]

          Devuelve solo JSON válido con esta forma:
          {"summary":"resumen breve","highlights":[{"reference":"income_spending_pattern","explanation":"por qué merece atención","recommendation":"qué podría revisar"}]}
        PROMPT
      end
    end
  end
end

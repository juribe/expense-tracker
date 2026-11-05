# frozen_string_literal: true

module Ai
  module Tasks
    # Interprets the deterministic savings analysis. The backend sends only
    # aggregated results and the references it computed; the model may explain
    # and prioritize them but must not invent amounts, merchants or categories.
    #
    # data: { "summary" => String, "highlights" => [{ "reference" =>, "explanation" =>, "recommendation" => }] }
    class SavingsOpportunityAnalysis < Base
      MAX_HIGHLIGHTS = 20

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
        # The backend owns every number on the page. A response that invents a
        # figure cannot be trusted, so it is rejected and the deterministic
        # copy is used instead.
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
        end.first(MAX_HIGHLIGHTS)

        { data: { "summary" => summary, "highlights" => highlights }, confidence: nil }
      end

      private

      def system_prompt(context)
        references = Array(context[:allowed_references])

        <<~PROMPT
          Eres el analista de finanzas personales de Yogasto. Recibes resultados
          ya calculados por el backend: gasto actual por categoría, promedio de
          meses anteriores, variaciones, pagos recurrentes detectados y pequeños
          gastos agrupados.

          Reglas obligatorias:
          - No inventes cifras, comercios, categorías ni movimientos.
          - No escribas importes ni porcentajes en tu texto: la interfaz muestra
            todas las cifras calculadas por el backend. Describe solo tendencias
            y hábitos.
          - No afirmes que el usuario ahorrará una cantidad. Habla de
            oportunidades, revisión y decisiones del usuario.
          - No asegures que un pago es prescindible; solo sugiere revisarlo.
          - No menciones deuda, inversiones ni datos que no estén en la entrada.
          - Usa un tono neutral, respetuoso y fácil de entender, en español.
          - Para cada hallazgo usa exactamente una de las referencias permitidas.

          Referencias permitidas: [#{references.join(", ")}]

          Devuelve solo JSON válido con esta forma:
          {"summary":"resumen breve","highlights":[{"reference":"category:...","explanation":"por qué merece atención","recommendation":"qué podría revisar"}]}
        PROMPT
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Tasks
    # Conversational (text/voice) expense extraction. The caller runs the
    # deterministic parser first and only routes here when the heuristic
    # result is missing or not confident enough. Cheap model first; the
    # strong model handles low-confidence or complex messages.
    #
    # input:   "Me gasté 20mil hoy en almuerzo"
    # context: { user:, today: Date, categories: [Category, ...], context: "optional hint" }
    # data:    [ { amount:, category:, description:, transaction_date:,
    #              confidence:, create_category: }, ... ]
    class ExpenseExtraction < Base
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
        { data: entries, confidence: confidences.min }
      end

      private

      def confidence_of(entry)
        value = entry["confidence"]
        value.is_a?(Numeric) ? Float(value).clamp(0.0, 1.0) : 0.5
      end

      def system_prompt(context)
        today = context[:today] || Date.current
        categories = Array(context[:categories]).map(&:name).join(", ")
        hint = context[:context].presence
        context_block = hint ? "\nContext: #{hint}\n" : ""
        <<~PROMPT
          You extract expense records from natural language (Spanish/Colombian usage).
          Current date: #{today.to_date.iso8601}. Currency: COP.
          User's existing categories: [#{categories}].
          #{context_block}
          Rules:
          - One input may contain multiple expenses; return one entry per expense.
          - Interpret Colombian amounts: "50 mil"/"50 lucas"/"50k" = 50000, "50.000 pesos" = 50000, "medio millon" = 500000.
          - Resolve relative dates ("hoy", "ayer", "anteayer", "el lunes") to an ISO date (YYYY-MM-DD).
          - Category: use one of the user's existing categories (SPANISH label) when it clearly fits; when the closest existing category differs only in wording, prefer it; otherwise set "create_category": true and suggest a short SPANISH category name.
          - UNASSIGNED CATEGORY: return "category": null (with "create_category": false) ONLY when the message gives no basis to determine or propose ANY category (truly empty/gibberish input). When a product or service IS identifiable but fits none of the user's categories, you MUST propose a new category with "create_category": true and a short Spanish name. Do NOT force ambiguous cases into "Otros".
          - "Otros" is ONLY for expenses that are known but fit none of the specific categories. "Otros" is NEVER an automatic fallback for uncertain classifications.
          - Do not invent context: never decide that an expense is personal, business-related or freelance work unless the message says so. Example: "I paid 65000 for Canva Pro" -> propose "Suscripciones" with "create_category": true (Canva is a digital subscription); "...for my business" -> "Negocio"; "...for my freelance work" -> "Trabajo independiente".
          - Application business rules (take priority over generic real-world meaning):
            * Dining, restaurants and food delivery (Didi, Didi Food, Rappi, domicilios, eating out) -> "Restaurante", which is a subcategory of "Comida"; never "Transporte" for Didi.
            * Netflix, Spotify and Disney+ are entertainment: -> "Entretenimiento", never "Servicios públicos".
            * Microsoft 365, Canva, ChatGPT, Adobe, Google One, iCloud, Dropbox and all other digital SaaS subscriptions -> propose "Suscripciones" (create_category: true) or another fitting category. NEVER classify any of these as "Servicios públicos".
            * "Servicios públicos" is reserved for actual utilities: water, electricity, gas, internet, telephone/mobile phone service. Never classify digital services or subscriptions as "Servicios públicos".
            * House maintenance/upkeep, repairs, rent, and condominium/management fees are "Hogar". "Servicios públicos" is NEVER used for them.
            * Parking (parqueadero, estacionamiento, parqueo, parking) -> "Transporte", never "Hogar".
          - Subcategory "d1" exists under "Comida". When the expense belongs to d1, always use "category": "Comida" (never "d1" as the main category).
          - Include a confidence between 0 and 1; reserve values below 0.9 for genuinely ambiguous inputs.
          Respond with ONLY JSON of the shape:
          {"expenses":[{"amount":50000,"category":"Restaurante","description":"Restaurante","transaction_date":"#{today.to_date.iso8601}","confidence":0.95,"create_category":false}]}
        PROMPT
      end
    end
  end
end

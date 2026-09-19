
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

        # Confidence is never taken from the model: every entry is re-scored
        # from deterministic signals against the original user input.
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
          ParsedExpense.build_expense(entry.merge("confidence" => score))
        end

        raise InvalidResponse, "no usable expense entries" if expenses.empty?

        {
          data: expenses,
          confidence: expenses.map(&:confidence).max || 0.0
        }
      end

      private

      def system_prompt(context)
        today = (context[:today] || Date.current).to_date.iso8601

        categories = Array(context[:categories]).map do |category|
          category.respond_to?(:name) ? category.name : category.to_s
        end.join(", ")

        hint = context[:context].presence
        context_block = hint ? "\nAdditional context: #{hint}\n" : ""

        <<~PROMPT
          Extract expenses from the user's natural-language message.
          The message may contain one or multiple expenses. Return each distinct
          transaction as a separate expense object.

          #{context_block}

          Today: #{today}
          Currency: COP
          Available categories: [#{categories}]

          For each expense return:

          - original_text: the exact portion of the user's message that describes
            this expense. Preserve the original wording. This field is used by
            downstream processing, so do not invent or rewrite it.
          - amount: integer amount in COP. Examples: "50 mil" = 50000,
            "50 lucas" = 50000, "50k" = 50000.
          - date: YYYY-MM-DD. Resolve relative dates using Today. Use null when
            the date cannot be determined reliably.
          - description: short, natural description of the expense.
          - category: use the most appropriate available category. Only suggest
            a new general category when none of the available categories fits.

          Rules:

          - Return every distinct expense in the message.
          - Separate transactions even when they use the same payment method.
          - Keep items from the same purchase as one expense unless the user
            clearly describes separate transactions.
          - Do not invent missing information.
          - Do not create merchant IDs, database IDs, or other entities.
          - A payment method mentioned once may apply to multiple expenses;
            do not create a separate expense for it.
          - original_text must come directly from the user's message.
          - Return only valid JSON. No markdown or explanations.

          Output:

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
